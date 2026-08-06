#!/usr/bin/env bash
set -euo pipefail

# One job: make sure this machine has a usable Infisical session, and do nothing
# else. It writes no files and never reads a secret value, so it is safe to run
# again at any time - an existing session makes it a no-op.
#
# It used to take an action argument, and `fetch` wrote the environment to `.env`.
# Both actions are gone. The guard below is why that removal is visible instead of
# silent: muscle memory typing the old form gets told, rather than being logged in
# and left believing a `.env` was written.
[ "$#" -gt 0 ] && echo "❌ secrets.sh takes no arguments; it only ensures an Infisical session ('$1' is not an action)" >&2 && exit 1

api_url="${INFISICAL_API_URL:-https://secrets.atomi.cloud}"
export INFISICAL_API_URL="${api_url}"

# `user get token` is the cheapest question that needs a valid session to answer.
# Its output is a token, so it is discarded rather than shown; only the exit status
# is read.
if infisical user get token --silent >/dev/null 2>&1; then
  echo "✅ Already logged into Infisical at ${api_url}"
  exit 0
fi

# Interactive by design: this is a local developer helper, and logging in is the one
# thing it exists to do.
infisical login

echo "✅ Logged into Infisical at ${api_url}"
