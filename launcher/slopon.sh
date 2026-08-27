#!/bin/sh
# SlopOn launcher wrapper (macOS / Linux): resolve a Node runtime and exec the
# shared launcher core. Pure POSIX sh — runs under dash and macOS bash 3.2.
set -u

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1

if [ -x "$dir/../node-runtime/bin/node" ]; then
  NODE_BIN="$dir/../node-runtime/bin/node"
elif command -v node >/dev/null 2>&1; then
  NODE_BIN=node
else
  echo "error: Node.js not found — re-run the SlopOn installer to provision a bundled runtime, or install Node 20/22 and retry." >&2
  exit 1
fi

exec "$NODE_BIN" "$dir/launcher.mjs" "$@"
