#!/usr/bin/env bash
set -euo pipefail

command -v entr >/dev/null 2>&1 || {
  echo "❌ entr is required for pls test:watch" >&2
  exit 1
}

rg --files lib test | entr -r dart test test/unit test/conformance
