# rsnapshotx

A wrapper around [rsnapshot](https://rsnapshot.org/) for backing up hosts that are not always
online, such as laptops and phones.

## Overview

With plain rsnapshot, a `daily` that cron starts while the laptop is away is simply lost.
rsnapshotx records each requested level as *pending* and keeps it pending until it succeeds:

- cron requests each retain level (`daily`, `weekly`, `monthly`, ...), and a frequent `retry`
  runs whatever is still pending
- before the first level syncs, every ssh source must be reachable. While a host is offline the
  level stays pending, and this is not an error
- a higher level waits until the oldest snapshot of the level below exists (e.g. `daily.6` for
  `retain daily 7`), and pending levels run highest first
- several configs (`-c`, repeatable) run one after the other, each with its own lock, so a broken
  config or an unmounted backup disk fails only that config
- optionally, `--email` mails the status of each config, through `mail` or through an SMTP relay
  with msmtp

## Requirements

- root, bash >= 5, GNU coreutils, util-linux (`flock`), rsnapshot
- optional: moreutils (`chronic`), and `mail` or `msmtp` for `--email`

Each rsnapshot config needs:

- `sync_first 1`
- a `lockfile`
- a `snapshot_root` that already exists. The state is kept there, and a missing root fails the
  config
- `no_create_root 1` is recommended, so that rsnapshot run by hand also fails when the backup disk
  is not mounted, instead of filling `/`

## Installing

```sh
sudo ./install.sh
```

This installs `rsnapshotx` into `/usr/local/bin`. Set `PREFIX` to install elsewhere, e.g.
`sudo PREFIX=/opt/rsnapshotx ./install.sh` installs into `/opt/rsnapshotx/bin`. To install by hand
instead:

```sh
sudo install -m 755 rsnapshotx /usr/local/bin/rsnapshotx
```

### Scheduling with cron

Example `/etc/cron.d/rsnapshotx` for two configs:

```
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=root

# m  h     dom mon dow user command
# monthly, on the 1st
5    0     1   *   *   root chronic -v rsnapshotx -c /etc/rsnapshot/laptop.conf monthly
5    1     1   *   *   root chronic -v rsnapshotx -c /etc/rsnapshot/server.conf monthly

# weekly, on Sundays
10   0     *   *   0   root chronic -v rsnapshotx -c /etc/rsnapshot/laptop.conf weekly
10   1     *   *   0   root chronic -v rsnapshotx -c /etc/rsnapshot/server.conf weekly

# daily
15   0     *   *   *   root chronic -v rsnapshotx -c /etc/rsnapshot/laptop.conf daily
15   1     *   *   *   root chronic -v rsnapshotx -c /etc/rsnapshot/server.conf daily

# hourly retry of anything pending, one config after the other
0    2-23  *   *   *   root chronic -v rsnapshotx -c /etc/rsnapshot/laptop.conf -c /etc/rsnapshot/server.conf retry
```

- Each config gets its own hour. Within that hour, monthly is requested before weekly and weekly
  before daily, so that the higher levels are already pending when daily runs them all, highest
  first.
- The `retry` line picks up anything still pending: a host that was offline, a level waiting for a
  lower snapshot, or a level that failed. A host that comes online at any time during the retry
  window gets backed up.
- `chronic` prints the output only when the command exits non-zero, so cron mails failures
  (to `MAILTO`) and stays quiet otherwise. An offline host is not a failure.

## Usage

```
rsnapshotx [options] [-c cfgfile]... command [args]
```

| Command | What it does |
|---|---|
| `<level>` | a retain level of the config: request it, then run everything pending |
| `retry` | run everything pending |
| anything else | passed to rsnapshot (`configtest`, `du`, `diff`, ...) |

Options:

- `-c`, `-t`, `-v`, `-V`, `-q`, `-D`, `-x` are rsnapshot's options. `-t` only shows what would be
  done and writes no state.
- `--email [--to addr] [--from addr] [--relayhost host:port]` mails the status of each config.
  `--relayhost` uses msmtp, with no TLS and no auth.
- `--trace` shows every command (`set -x`).

`rsnapshotx --help` prints the full reference, including the state files and exit codes.

### ssh-agent

To use a key with a passphrase, load it once into a long-lived agent:

```sh
sudo rsnapshotx --start-ssh-agent ~/.ssh/id_backup   # args go to ssh-add
sudo rsnapshotx --stop-ssh-agent
```

While its socket (`/run/rsnapshot/rsnapshotx.agent.sock`) exists, every run uses that agent.

### Running in Docker

rsnapshotx can also run from a plain Debian container, for example on a host where you don't want
to install rsnapshot:

```sh
sudo rsnapshotx --start-ssh-agent /root/.ssh/id_backup
sudo docker run --rm -it --init \
  -v /etc/localtime:/etc/localtime:ro \
  -v /usr/local/bin/rsnapshotx:/usr/local/bin/rsnapshotx:ro \
  -v /etc/rsnapshot:/etc/rsnapshot:ro \
  -v /root/.ssh:/root/.ssh \
  -v /backup:/backup \
  -v /run/rsnapshot:/run/rsnapshot \
  -v /var/log/rsnapshot:/var/log/rsnapshot \
  debian bash -c '
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      rsnapshot openssh-client msmtp > /dev/null &&
    rsnapshotx --email --relayhost <smtp-host>:25 --to you@example.com --from backup@example.com \
      -c /etc/rsnapshot/laptop.conf -c /etc/rsnapshot/server.conf daily'
sudo rsnapshotx --stop-ssh-agent
```

- Mounting `/run/rsnapshot` shares the locks and the agent socket with the host.
- `--relayhost` sends the mail through an SMTP server reachable from the container, as the host's
  `mail` command is not available there.
- Adjust the mounts to your `snapshot_root` and `logfile`. Depending on your network, the container
  may need its own network setup (e.g. a macvlan network) to reach the hosts.

## Testing

There is no test suite. To check a setup:

```sh
sudo rsnapshotx -c /etc/rsnapshot/laptop.conf configtest   # passed to rsnapshot
sudo rsnapshotx -t -c /etc/rsnapshot/laptop.conf daily     # test run: shows what would run, writes no state
shellcheck rsnapshotx
```

## License

MIT, see [LICENSE](LICENSE).
