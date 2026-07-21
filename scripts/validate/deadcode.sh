#!/usr/bin/env bash
set -euo pipefail

# Two dead-code passes (R12), NO exclusion lists.
#
# Pass 1 (as-is): analyze the whole package (lib + test); the analyzer flags
# unused private elements, unused imports, and unreachable code.
# Pass 2 (production only): analyze lib WITHOUT the tests present, so a helper
# that only the test tree keeps alive shows up as unused in the production
# graph rather than being masked by a test import.
#
# Production purity: `lib/` (including the dependency-light test_helper
# sub-library) must NEVER import the test framework.

echo "🧹 dead-code pass 1 (as-is: lib + test)"
dart analyze lib test

echo "🧹 dead-code pass 2 (production only: lib)"
dart analyze lib

if grep -rEn "package:(test|matcher|mockito|flutter_test)" lib >/dev/null 2>&1; then
  echo "❌ lib/ imports a test framework — production graph is impure" >&2
  grep -rEn "package:(test|matcher|mockito|flutter_test)" lib >&2 || true
  exit 1
fi

echo "✅ dead-code: both passes clean, no exclusion lists, production graph pure"
