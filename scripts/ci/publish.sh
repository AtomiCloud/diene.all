#!/usr/bin/env bash
set -euo pipefail

# pub.dev publish path for the mirror repo (AtomiCloud/diene.dart_auth_engine).
#
# AUTHORED, NOT EXECUTED in this lane: publication, tagging, and mirror-repo CD
# are conductor-owned after all eight Dart branches return. This script is the
# reference the mirror CD runs; running it locally is forbidden by the lane hold.
#
# Credentials: PUB_CREDENTIALS_JSON (GitHub secret) is written to the pub config
# dir by the CD environment before this runs.

tag="${1:-${GITHUB_REF_NAME:-}}"

echo "🏷️  Verifying manifest == tag..."
./scripts/validate/manifest-tag.sh "${tag}"

echo "📦 Resolving dependencies..."
flutter pub get

echo "📮 Publish dry-run (must be clean before the real publish)..."
flutter pub publish --dry-run

echo "🚀 Publishing to pub.dev..."
flutter pub publish --force

echo "✅ Published diene_auth_engine ${tag}"
