#!/usr/bin/env bash
set -euo pipefail

go vet ./...

echo "✅ Go vet passed"
