#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Resolving Dart dependencies..."
dart pub get
dart analyze
dart test

echo "✅ Dart analyze and tests passed"
