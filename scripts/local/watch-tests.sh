#!/usr/bin/env bash
set -euo pipefail

command -v entr >/dev/null 2>&1 || {
  echo "❌ entr is required for pls test:watch" >&2
  exit 1
}

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}/packages/diene_dart_lib"

rg --files lib test | entr -r dart test test/unit test/conformance
