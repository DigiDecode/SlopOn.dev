#!/bin/sh
# SlopOn launcher wrapper (macOS / Linux): resolve a Node runtime and exec the
# shared launcher core. Pure POSIX sh — runs under dash and macOS bash 3.2.
set -u

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1

NODE_BIN=""
if [ -x "$dir/../node-runtime/bin/node" ]; then
  NODE_BIN="$dir/../node-runtime/bin/node"
elif [ -r "$dir/node.path" ]; then
  # Absolute Node recorded by the installer: menu/shortcut launches (GNOME,
  # .desktop) run with a minimal PATH — no nvm or user dirs — so bare `node`
  # is not reliable there.
  baked_node=$(cat "$dir/node.path" 2>/dev/null)
  if [ -n "$baked_node" ] && [ -x "$baked_node" ]; then
    NODE_BIN="$baked_node"
  fi
fi
if [ -z "$NODE_BIN" ] && command -v node >/dev/null 2>&1; then
  NODE_BIN=node
fi
if [ -z "$NODE_BIN" ]; then
  echo "error: Node.js not found — re-run the SlopOn installer to provision a bundled runtime, or install Node 20/22 and retry." >&2
  exit 1
fi

exec "$NODE_BIN" "$dir/launcher.mjs" "$@"
