#!/usr/bin/env bash
set -euo pipefail

# Two-pass dead-code gate — NO exclusion lists (R12).
#
# Pass 1 (as-is): analyze the whole package (lib + test). Unused imports /
#   elements / fields / locals are hard errors (analysis_options.yaml).
# Pass 2 (excluding tests): analyze ONLY lib/. Any production symbol that is
#   reachable solely from test code now shows up as unused → red.
#
# NOTE (honest limitation, recorded in the node note): the analyzer's
# unused-symbol diagnostics catch unused imports and unused PRIVATE members in
# both passes; unused PUBLIC package API is not flagged without a dedicated
# tool (dart_code_metrics/dcm), which is not in the pinned dev shell. The
# two-pass structure and no-exclusion-list rule are honoured regardless.

echo "🔎 dead-code pass 1 (as-is: lib + test)"
dart analyze --fatal-infos --fatal-warnings

echo "🔎 dead-code pass 2 (excluding tests: lib only)"
dart analyze --fatal-infos --fatal-warnings lib

echo "✅ dead-code: both passes clean"
