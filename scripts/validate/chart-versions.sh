#!/usr/bin/env bash
set -euo pipefail

# ONE semver spans the image tag and BOTH charts (R20). Kargo aligns on chart `version` ==
# image `Tag`, and `appVersion` is the image version too, so five values must agree with the
# repository VERSION file.
#
# This is a GATE, so it is built to be able to go RED and it asserts on the VALUES it read,
# never on a command's silence: every version is printed next to the field it came from, and a
# missing file or a missing field is a hard failure naming which one. A structured query (yq)
# reads the YAML — never a grep, which cannot tell "the field says 0.0.0" apart from "the field
# is not there".

version_file="VERSION"
root_chart="infra/root_chart/Chart.yaml"
root_values="infra/root_chart/values.yaml"
primordial_chart="infra/primordial_chart/Chart.yaml"

semver='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'

for file in "${version_file}" "${root_chart}" "${root_values}" "${primordial_chart}"; do
  [ ! -f "${file}" ] && echo "❌ '${file}' is missing; refusing to report a match on absent data" >&2 && exit 1
done

expected="$(tr -d '[:space:]' <"${version_file}")"
[ -z "${expected}" ] && echo "❌ '${version_file}' is empty" >&2 && exit 1
[[ ${expected} =~ ${semver} ]] || {
  echo "❌ VERSION '${expected}' is not a semver" >&2
  exit 1
}

# Read one field out of one YAML file, failing loudly when it is absent or null. `yq` prints
# the string "null" for a missing key, which is exactly the value that must never be silently
# treated as a match.
read_field() {
  local file="$1" expression="$2" label="$3" value
  value="$(yq -r "${expression}" "${file}")"
  if [ -z "${value}" ] || [ "${value}" = "null" ]; then
    echo "❌ ${label} is absent from '${file}'; refusing to report a match on missing data" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

root_version="$(read_field "${root_chart}" '.version' 'root_chart.version')"
root_app_version="$(read_field "${root_chart}" '.appVersion' 'root_chart.appVersion')"
primordial_version="$(read_field "${primordial_chart}" '.version' 'primordial.version')"
primordial_app_version="$(read_field "${primordial_chart}" '.appVersion' 'primordial.appVersion')"

# The image tag is deliberately EMPTY in values.yaml: the chart falls back to its own
# appVersion, which is what CD pins to the released semver. An empty tag is therefore the
# app chart's appVersion, and a non-empty one is an explicit pin that must still agree.
# `// ""` distinguishes "declared empty" (correct) from "key absent" (a real defect).
image_tag_raw="$(yq -r '.image.tag // "«absent»"' "${root_values}")"
if [ "${image_tag_raw}" = "«absent»" ] || [ "${image_tag_raw}" = "null" ]; then
  echo "❌ image.tag is absent from '${root_values}'; refusing to report a match on missing data" >&2
  exit 1
fi
if [ -z "${image_tag_raw}" ]; then
  image_tag="${root_app_version}"
  image_tag_note="(values image.tag is empty -> chart appVersion)"
else
  image_tag="${image_tag_raw}"
  image_tag_note="(values image.tag is pinned)"
fi

matched=0
failed=0
check() {
  local label="$1" value="$2"
  if [ "${value}" = "${expected}" ]; then
    matched=$((matched + 1))
  else
    failed=$((failed + 1))
    echo "❌ ${label}='${value}' does not equal VERSION='${expected}'" >&2
  fi
}

check 'root_chart.version' "${root_version}"
check 'root_chart.appVersion' "${root_app_version}"
check 'primordial.version' "${primordial_version}"
check 'primordial.appVersion' "${primordial_app_version}"
check 'image.tag' "${image_tag}"

total=$((matched + failed))
verdict="$([ "${failed}" -eq 0 ] && echo MATCH || echo MISMATCH)"
echo "VERSION=${expected}  root_chart.version=${root_version}  root_chart.appVersion=${root_app_version}"
echo "primordial.version=${primordial_version}  primordial.appVersion=${primordial_app_version}  image.tag=${image_tag} ${image_tag_note}"
echo "-> ${matched}/${total} ${verdict}"

[ "${failed}" -ne 0 ] && echo "❌ ${failed} of ${total} version fields disagree with '${version_file}'" >&2 && exit 1

echo "✅ One semver ${expected} spans the image tag and both charts"
