#!/usr/bin/env bash
set -euo pipefail

go test -count=1 -run '^Example' ./...

# Compiling whatever examples happen to exist is not enough: enforce that every
# exported production and TestHelper symbol has an associated Example function.
go run scripts/validate/examples_coverage.go lib/config testhelper

echo "✅ Go examples compile and pass with full exported-symbol coverage"
