#!/usr/bin/env bash
# R21 rebrand static gate.
#
# Every identity, branding and SSO value must be CONFIG-DRIVEN. This gate reads the
# real values out of the base settings layer and then proves none of them is also
# written into the C# sources, where a rebrand could not reach it.
#
# Design notes, because the obvious implementations of this check are all vacuous:
#   * It asserts on VALUES. It prints every value it compared and the final counts,
#     so "verified" can never be confused with "never ran".
#   * It reads the settings with yq — a structured query — not with grep, so a
#     formatting change cannot silently empty the subject list.
#   * It REFUSES to report clean on an empty subject set. Zero values to check or
#     zero source files to scan is a could-not-look, not a pass.
#   * The scanner enumerates files from `git ls-files -z`, NUL-delimited, rather
#     than from a glob: `git ls-files` octal-quotes non-ASCII names, and a glob
#     over a filename list fails silently on encoding.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${root}"

settings="App/Config/settings.yaml"
scan_root="App"

[ -f "${settings}" ] || {
  echo "❌ rebrand: ${settings} not found — cannot determine the config-driven values" >&2
  exit 1
}
command -v yq >/dev/null || {
  echo "❌ rebrand: yq is required to read ${settings}" >&2
  exit 1
}

# ── the values that MUST live in configuration, read from configuration itself ──
# Each entry is "<config path>" and is resolved through yq. A path that resolves to
# null or empty is skipped and reported, never treated as a silent pass.
paths=(
  '.app.landscape'
  '.app.platform'
  '.app.service'
  '.app.module'
  '.error_portal.host'
  '.http.open_api.title'
  '.http.open_api.description'
  '.auth.audience'
  '.auth.home_landscape_claim'
  '.auth.logto.endpoint'
  '.auth.logto.issuer'
  '.auth.logto.app_id'
  '.auth.logto.management.endpoint'
  '.auth.logto.management.resource'
  '.auth.logto.management.client_id'
  '.auth.handoff.mount'
)

declare -a names=()
declare -a values=()
declare -a skipped=()

for path in "${paths[@]}"; do
  value="$(yq -r "${path} // \"\"" "${settings}")"
  if [ -z "${value}" ] || [ "${value}" = "null" ]; then
    skipped+=("${path} (blank in the base layer — injected per landscape)")
    continue
  fi
  names+=("${path}")
  values+=("${value}")
done

# ── the sources to scan ──
mapfile -d '' -t sources < <(git ls-files -z -- "${scan_root}/**/*.cs" "${scan_root}/*.cs")

echo "🔎 rebrand gate"
echo "   settings : ${settings}"
echo "   sources  : ${#sources[@]} tracked .cs file(s) under ${scan_root}/"
echo "   values   : ${#values[@]} config-driven value(s), ${#skipped[@]} blank-and-skipped"

# REFUSE ON EMPTY. Both of these mean the gate could not look, and returning clean
# here is precisely how a guard becomes decorative.
if [ "${#values[@]}" -eq 0 ]; then
  echo "❌ rebrand: no config-driven values resolved from ${settings}; refusing to report clean" >&2
  exit 1
fi
if [ "${#sources[@]}" -eq 0 ]; then
  echo "❌ rebrand: no tracked C# sources found under ${scan_root}/; refusing to report clean" >&2
  exit 1
fi

# The generated schema and the settings files legitimately contain these values.
# Only C# sources are scanned, so nothing needs excluding — but say so explicitly
# rather than leaving a reader to wonder.
findings=0
checked=0

for index in "${!values[@]}"; do
  name="${names[${index}]}"
  value="${values[${index}]}"
  checked=$((checked + 1))

  # Match the value as a C# string literal. -F is a fixed string, so a value
  # containing regex metacharacters cannot silently match nothing.
  hits="$(grep -Fn "\"${value}\"" -- "${sources[@]}" 2>/dev/null || true)"

  if [ -n "${hits}" ]; then
    echo "   ❌ ${name} = \"${value}\" is HARDCODED:"
    while IFS= read -r hit; do echo "        ${hit}"; done <<<"${hits}"
    findings=$((findings + 1))
  else
    echo "   ✅ ${name} = \"${value}\" — config-only"
  fi
done

echo "   skipped:"
if [ "${#skipped[@]}" -eq 0 ]; then
  echo "        (none)"
else
  printf '        %s\n' "${skipped[@]}"
fi

echo "📊 rebrand: ${checked} value(s) checked, $((checked - findings)) config-only, ${findings} hardcoded"

if [ "${findings}" -ne 0 ]; then
  echo "❌ rebrand: ${findings} identity/branding/auth value(s) are hardcoded in C# sources." >&2
  echo "   Every one of these must come from configuration so a rebrand is a values change (R21)." >&2
  exit 1
fi

echo "✅ rebrand: every identity, branding and auth value is config-driven"
