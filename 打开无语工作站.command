#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
app="$HOME/Applications/无语工作站.app"
if [ ! -x "$app/Contents/MacOS/Bridge" ]; then
    "$root/build"
fi
exec /usr/bin/open "$app"
