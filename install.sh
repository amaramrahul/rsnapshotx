#!/bin/bash
# install.sh - install rsnapshotx into $PREFIX/bin (default /usr/local/bin)
#
# Usage:
#   sudo ./install.sh
#   sudo PREFIX=/opt/rsnapshotx ./install.sh

set -euo pipefail

PREFIX=${PREFIX:-/usr/local}
src_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
src=$src_dir/rsnapshotx
dest=$PREFIX/bin/rsnapshotx

if (( EUID != 0 )); then
    echo "install.sh: must be run as root (try: sudo $0)" >&2
    exit 1
fi

if [[ ! -f $src ]]; then
    echo "install.sh: $src not found" >&2
    exit 1
fi

install -D -m 755 -- "$src" "$dest"
echo "installed $dest"

# An older copy in /usr/local/sbin comes first in PATH and would shadow the new one.
old=/usr/local/sbin/rsnapshotx
if [[ -e $old && $old != "$dest" ]]; then
    echo "warning: an older copy exists at $old and comes first in PATH; remove it with:" >&2
    echo "  sudo rm $old" >&2
fi

for cmd in rsnapshot flock; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "warning: '$cmd' not found; rsnapshotx needs it to run" >&2
    fi
done
