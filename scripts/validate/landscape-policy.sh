#!/usr/bin/env bash
set -euo pipefail

count="$(rg -l 'FLUTTER_BASE_LANDSCAPE' lib --glob '*.dart' | wc -l | tr -d ' ')"
[ "${count}" -ne 1 ] && echo "❌ landscape must have exactly one compile-time source" >&2 && exit 1
rg -q "static const String compiledLandscape = String\.fromEnvironment" lib/config/app_config.dart || {
  echo "❌ landscape is not a compile-time constant" >&2
  exit 1
}
if rg -n 'Platform\.environment|Uri\.base\.host|host(name)?|packageName.*landscape|applicationId.*landscape' lib --glob '*.dart'; then
  echo "❌ runtime landscape detection is forbidden" >&2
  exit 1
fi
if rg -n 'landscape.*(Dropdown|Selector|switcher)|kReleaseMode.*landscape' lib --glob '*.dart'; then
  echo "❌ release code contains a runtime landscape switcher" >&2
  exit 1
fi

echo "✅ landscape is baked at build/stamp time with no runtime detection"
