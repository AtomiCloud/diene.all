#!/usr/bin/env bash
set -euo pipefail

go test -count=1 -run '^Example' ./...

echo "✅ Go examples compile and pass"
