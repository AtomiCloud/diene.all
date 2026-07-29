#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Resolving Flutter dependencies..."
flutter pub get
flutter analyze
flutter test

echo "✅ Flutter analyze and tests passed"
