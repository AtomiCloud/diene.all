#!/usr/bin/env bash
set -euo pipefail

# Package hygiene gate. `dart pub publish --dry-run` exits non-zero on WARNINGS
# and on the session-only dependency-override HINTS. This node is stacked via
# gitignored session-only compatibility packages (see pubspec_overrides.yaml),
# so pub emits exactly one hint per overridden sibling dependency — expected,
# and gone at the deterministic swap. The gate therefore asserts ZERO WARNINGS
# (hints are allowed) rather than trusting the exit code.

out="$(dart pub publish --dry-run 2>&1 || true)"
printf '%s\n' "${out}" | tail -8

warnings="$(printf '%s' "${out}" | sed -n 's/^Package has \([0-9][0-9]*\) warning.*/\1/p')"
warnings="${warnings:-0}"

if printf '%s' "${out}" | grep -qiE 'Package validation found the following [0-9]* error'; then
  echo "❌ publish dry-run reported errors" >&2
  exit 1
fi
if [ "${warnings}" != "0" ]; then
  echo "❌ publish dry-run reported ${warnings} warning(s)" >&2
  exit 1
fi

echo "✅ publish dry-run: 0 warnings (session-only override hints are expected)"
