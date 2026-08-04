#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# This oracle deliberately does not consume skills-sync's staging manifest. It
# derives external Dart obligations from tracked pubspecs and expected vendored
# packages from package_config.json, so a broken generator cannot agree with its
# own output and make the freshness gate pass.
dart_manifests="${work_dir}/dart-manifests.zlist"
dart_declared_raw="${work_dir}/dart-declared-raw.txt"
dart_declared="${work_dir}/dart-declared.txt"
if ! git ls-files -z -- '*pubspec.yaml' >"${dart_manifests}"; then
  echo "❌ Failed to list tracked Dart manifests (git ls-files)" >&2
  exit 1
fi
: >"${dart_declared_raw}"
while IFS= read -r -d '' manifest; do
  if ! yq -o=json '.' "${manifest}" |
    jq -r '
      [
        (.dependencies // {}),
        (.dev_dependencies // {}),
        (.dependency_overrides // {})
      ]
      | add
      | keys[]
      | select(startswith("diene_"))
    ' >>"${dart_declared_raw}"; then
    echo "❌ Failed to inspect Dart dependencies in ${manifest}" >&2
    exit 1
  fi
done <"${dart_manifests}"
LC_ALL=C sort -u "${dart_declared_raw}" >"${dart_declared}"
dart_declared_count="$(wc -l <"${dart_declared}")"

package_config=".dart_tool/package_config.json"
pub_entries="${work_dir}/pub-entries.tsv"
pub_names="${work_dir}/pub-names.txt"
if [ "${dart_declared_count}" -gt 0 ] && [ ! -f "${package_config}" ]; then
  echo "❌ External diene Dart dependencies are declared, but ${package_config} is missing" >&2
  echo "❌ Refusing to touch committed vendored skills without an independent resolver inventory" >&2
  exit 1
fi
if [ -f "${package_config}" ]; then
  if ! jq -e '.packages | type == "array"' "${package_config}" >/dev/null; then
    echo "❌ Invalid Dart package configuration: ${package_config}" >&2
    exit 1
  fi
  if ! jq -r '.packages[] | select(.name | startswith("diene_")) | [.name, .rootUri] | @tsv' \
    "${package_config}" >"${pub_entries}"; then
    echo "❌ Failed to derive Dart package entries from ${package_config}" >&2
    exit 1
  fi
  cut -f1 "${pub_entries}" | LC_ALL=C sort -u >"${pub_names}"
else
  : >"${pub_entries}"
  : >"${pub_names}"
fi

while IFS= read -r declared_package; do
  [ -n "${declared_package}" ] || continue
  config_status=0
  grep -F -x -q "${declared_package}" "${pub_names}" || config_status=$?
  if [ "${config_status}" -ge 2 ]; then
    echo "❌ Failed to inspect resolved Dart package names (grep exit ${config_status})" >&2
    exit "${config_status}"
  fi
  if [ "${config_status}" -ne 0 ]; then
    echo "❌ Declared Dart dependency ${declared_package} is absent from ${package_config}" >&2
    exit 1
  fi
done <"${dart_declared}"

bash scripts/local/skills-sync.sh

oracle_decode_uri_path() {
  local encoded=$1
  local decoded=""
  local prefix
  local hex
  local byte

  while [[ ${encoded} == *%* ]]; do
    prefix="${encoded%%\%*}"
    decoded+="${prefix}"
    encoded="${encoded#*%}"
    if [[ ! ${encoded} =~ ^([[:xdigit:]]{2})(.*)$ ]]; then
      echo "❌ Invalid percent escape in Dart package root URI" >&2
      return 1
    fi
    hex="${BASH_REMATCH[1]}"
    encoded="${BASH_REMATCH[2]}"
    printf -v byte '%b' "\\x${hex}"
    decoded+="${byte}"
  done

  printf '%s' "${decoded}${encoded}"
}

oracle_pub_root() {
  local root_uri=$1
  local package_path

  if [[ ${root_uri} == file://localhost/* ]]; then
    package_path="/${root_uri#file://localhost/}"
  elif [[ ${root_uri} == file:///* ]]; then
    package_path="${root_uri#file://}"
  elif [[ ${root_uri} == file://* ]]; then
    echo "❌ Unsupported authority in Dart package root URI: ${root_uri}" >&2
    return 1
  elif [[ ${root_uri} == /* ]]; then
    package_path="${root_uri}"
  else
    package_path=".dart_tool/${root_uri}"
  fi

  if [[ ${package_path} == *%* ]]; then
    package_path="$(oracle_decode_uri_path "${package_path}")" || return 1
  fi
  realpath -m -- "${package_path}"
}

while IFS=$'\t' read -r package root_uri; do
  [ -n "${package}" ] || continue
  if ! package_root="$(oracle_pub_root "${root_uri}")"; then
    echo "❌ Independent oracle could not resolve Dart package ${package}" >&2
    exit 1
  fi

  declared_status=0
  grep -F -x -q "${package}" "${dart_declared}" || declared_status=$?
  if [ "${declared_status}" -ge 2 ]; then
    echo "❌ Failed to inspect declared Dart dependencies (grep exit ${declared_status})" >&2
    exit "${declared_status}"
  fi
  if [ ! -d "${package_root}" ]; then
    if [ "${declared_status}" -eq 0 ]; then
      echo "❌ Resolved Dart dependency ${package} has no package root at ${package_root}" >&2
      exit 1
    fi
    continue
  fi

  skills_dir="${package_root}/skills"
  [ -d "${skills_dir}" ] || continue
  [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || continue
  vendored_package="${vendor_dir}/${package}"
  if [ ! -d "${vendored_package}" ] || [ -z "$(find "${vendored_package}" -type f -print -quit)" ]; then
    echo "❌ Dart package ${package} has skills but no matching nonempty vendored directory" >&2
    exit 1
  fi
done <"${pub_entries}"

tracked="${work_dir}/tracked.txt"
if ! git ls-files -- "${vendor_dir}" >"${tracked}"; then
  echo "❌ Failed to list tracked vendored skills (git ls-files)" >&2
  exit 1
fi

# .gitkeep only keeps the directory alive; it can never witness stale content.
subjects="${work_dir}/subjects.txt"
subjects_status=0
grep -F -x -v "${vendor_dir}/.gitkeep" "${tracked}" >"${subjects}" || subjects_status=$?
if [ "${subjects_status}" -ge 2 ]; then
  echo "❌ Failed to filter tracked vendored skills (grep exit ${subjects_status})" >&2
  exit "${subjects_status}"
fi
subject_count="$(wc -l <"${subjects}")"

echo "ℹ️ Tracked vendored-skill subjects: ${subject_count}"
if [ "${subject_count}" -eq 0 ]; then
  echo "❌ No tracked subject under ${vendor_dir}; the freshness gate would pass vacuously" >&2
  exit 1
fi

porcelain="${work_dir}/porcelain.txt"
if ! git status --porcelain=v1 --untracked-files=all -- "${vendor_dir}" >"${porcelain}"; then
  echo "❌ Failed to inspect vendored-skill status (git status)" >&2
  exit 1
fi

# The index is the proposed tree, so an index-only entry (`A `, `M `, `R `) is
# the canonical regeneration a commit is about to record. Real drift is anything
# the worktree disagrees on after sync: a nonblank worktree column, which also
# covers every `??` untracked regeneration.
drift="${work_dir}/drift.txt"
drift_status=0
grep -E '^.[^ ] ' "${porcelain}" >"${drift}" || drift_status=$?
if [ "${drift_status}" -ge 2 ]; then
  echo "❌ Failed to filter vendored-skill status (grep exit ${drift_status})" >&2
  exit "${drift_status}"
fi
drift_count="$(wc -l <"${drift}")"
status_count="$(wc -l <"${porcelain}")"

echo "ℹ️ Vendored-skill status entries: ${status_count}"
echo "ℹ️ Vendored-skill drift entries: ${drift_count}"
if [ "${drift_count}" -ne 0 ]; then
  echo "❌ Vendored skills are stale; re-run ./scripts/local/skills-sync.sh and stage the result:" >&2
  cat "${drift}" >&2
  exit 1
fi

echo "✅ Vendored skills are fresh"
