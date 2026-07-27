#!/usr/bin/env bash
set -euo pipefail

count="$(rg -l 'FLUTTER_BASE_LANDSCAPE' lib --glob '*.dart' | wc -l | tr -d ' ')"
[ "${count}" -ne 1 ] && echo "❌ landscape must have exactly one compile-time source" >&2 && exit 1
rg -q "static const String compiledLandscape = String\.fromEnvironment" lib/config/app_config.dart || {
  echo "❌ landscape is not a compile-time constant" >&2
  exit 1
}
# Rule 3 forbids DERIVING the landscape at runtime. The term for a host must stay
# adjacent to `landscape`: a bare `host(name)?` banned the word "host" outright,
# which this template cannot obey — the deeplink router compares `uri.host`, the
# picker's baked endpoint-suffix allowlist calls `allowsHost()`, and the rescue
# router validates `seed.host`. Those are required features, not runtime
# detection. Doc comments are excluded so correct prose ("endpoints are hosted by
# dotnet-api") cannot fail the gate.
#
# The lookahead needs PCRE2, so this runs under `rg -P`. rc is captured DIRECTLY
# rather than via `if rg ...`: rg exits 0 for a match, 1 for no match, and 2 for
# an error (unsupported syntax, unreadable file). An `if` treats 2 the same as 1,
# which would turn a regex that never compiled into a clean-looking pass. Only
# rc=1 certifies "no matches"; rc>=2 is reported as a validator fault.
landscape_pattern='Platform\.environment|Uri\.base\.host|packageName.*landscape|applicationId.*landscape|^\s*(?!\s*///)[^\n]*\blandscape\b[^\n]*\bhost(name)?\b|^\s*(?!\s*///)[^\n]*\bhost(name)?\b[^\n]*\blandscape\b'
rule3_rc=0
rule3_out="$(rg -nP "${landscape_pattern}" lib --glob '*.dart')" || rule3_rc=$?
if [ "${rule3_rc}" -eq 0 ]; then
  printf '%s\n' "${rule3_out}"
  echo "❌ runtime landscape detection is forbidden" >&2
  exit 1
elif [ "${rule3_rc}" -ne 1 ]; then
  echo "❌ landscape rule-3 scan failed (rg rc=${rule3_rc}); refusing to certify" >&2
  exit 1
fi
if rg -n 'landscape.*(Dropdown|Selector|switcher)|kReleaseMode.*landscape' lib --glob '*.dart'; then
  echo "❌ release code contains a runtime landscape switcher" >&2
  exit 1
fi

echo "✅ landscape is baked at build/stamp time with no runtime detection"
