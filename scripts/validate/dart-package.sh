#!/usr/bin/env bash
set -euo pipefail

[[ $(yq -r '.name' pubspec.yaml) != "diene_result" ]] && echo "❌ pubspec name must be diene_result" >&2 && exit 1
[[ $(yq -r '.version' pubspec.yaml) != "$(cat VERSION)" ]] && echo "❌ pubspec.yaml and VERSION must match" >&2 && exit 1
[[ $(yq -r '.dependencies // {} | length' pubspec.yaml) -ne 0 ]] && echo "❌ diene_result must have zero runtime dependencies" >&2 && exit 1
[[ $(yq -r '.repository' pubspec.yaml) != "https://github.com/AtomiCloud/diene.dart_result" ]] && echo "❌ pubspec repository is not the snaked mirror" >&2 && exit 1

for file in lib/diene_result.dart lib/test_helper.dart doc/result.md skills/diene-result-usage/SKILL.md LICENSE README.md CHANGELOG.md; do
  [[ -f ${file} ]] || {
    echo "❌ required package artifact is missing: ${file}" >&2
    exit 1
  }
done

if rg -n "package:(test|matcher|mockito|mocktail)/" lib/test_helper.dart; then
  echo "❌ TestHelper must not depend on a test framework or mocking package" >&2
  exit 1
fi

echo "✅ Dart package identity, zero-runtime dependency graph, and TestHelper boundary conform"
