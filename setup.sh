#!/usr/bin/env bash
set -u                      # NOT set -e: failures are collected per-repo, script continues

BASE_URL="git@github.com:DigiDecode"
for arg in "$@"; do
  case "$arg" in
    --https) BASE_URL="https://github.com/DigiDecode" ;;
    *) echo "error: unknown argument '$arg' (usage: ./setup.sh [--https])"; exit 1 ;;
  esac
done

# AC2: git availability check first
if ! command -v git >/dev/null 2>&1; then
  echo "error: git is not installed or not on PATH"
  exit 1
fi

cd "$(dirname "$0")" || exit 1   # anchor to SlopOn.dev root regardless of invocation cwd

REPOS="slopon_frontend frontend
slopon_backend backend
gpt_markdown gpt_markdown
re-editor re-editor
re-highlight re-highlight"

FAILED=""
# bash 3.2 safe: here-string keeps the loop in the CURRENT shell (an `echo | while` pipe
# would run the loop in a subshell and FAILED would never propagate back). The here-string
# also appends a trailing newline, so the final line is never skipped by `read`.
while read -r repo dir; do
  [ -n "$repo" ] || continue
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo ">>> $dir: pulling updates"
    git -C "$dir" pull || FAILED="$FAILED $dir(pull)"
  elif [ -e "$dir" ]; then
    echo ">>> $dir: WARNING exists but is not a git repository, skipping"
    FAILED="$FAILED $dir(not-a-git-repo)"
  else
    echo ">>> $dir: cloning $BASE_URL/$repo.git"
    git clone "$BASE_URL/$repo.git" "$dir" || FAILED="$FAILED $dir(clone)"
  fi
done <<< "$REPOS"

# final summary
echo
if [ -n "$FAILED" ]; then
  echo "FAILED:$FAILED"
  exit 1
fi
echo "All repositories cloned/updated successfully."
exit 0
