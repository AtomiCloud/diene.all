#!/usr/bin/env bash
set -euo pipefail

# ### workspace
# #### source: workspace
vendor_dir=".claude/skills/vendor"
staging="$(mktemp -d .claude/skills/.vendor.XXXXXX)"
resolver_dir="$(mktemp -d)"
swap_dir=""
backup=""
swap_committed=false
cleanup() {
  local status=$?
  local rollback_failed=false
  trap - EXIT INT TERM
  set +e

  if [ -n "${backup}" ] && [ -e "${backup}" ]; then
    if [ ! -e "${vendor_dir}" ]; then
      if ! mv "${backup}" "${vendor_dir}"; then
        echo "❌ Failed to restore the previous vendored-skills tree" >&2
        rollback_failed=true
      fi
    elif [ "${swap_committed}" = false ]; then
      chmod -R u+w "${vendor_dir}" 2>/dev/null || true
      rm -rf "${vendor_dir}"
      if ! mv "${backup}" "${vendor_dir}"; then
        echo "❌ Failed to roll back the previous vendored-skills tree" >&2
        rollback_failed=true
      fi
    else
      chmod -R u+w "${backup}" 2>/dev/null || true
      rm -rf "${backup}"
    fi
  fi
  if [ -d "${staging}" ]; then
    chmod -R u+w "${staging}" 2>/dev/null || true
    rm -rf "${staging}"
  fi
  if [ -n "${swap_dir}" ] && [ -d "${swap_dir}" ]; then
    rm -rf "${swap_dir}"
  fi
  rm -rf "${resolver_dir}"
  if [ "${rollback_failed}" = true ]; then
    exit 1
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

node_declared=false
node_staged=false
nuget_declared=false
nuget_staged=false
go_declared=false
go_staged=false
pub_declared=false
pub_staged=false

touch "${staging}/.gitkeep"

# jq -e uses both 1 (false/null) and 4 (no output) for legitimate no-match
# results. Missing input, filter compilation, malformed input, and unknown
# future statuses must remain loud failures.
jq_match() {
  local status=0
  jq -e "$@" >/dev/null || status=$?
  case "${status}" in
  0) return 0 ;;
  1 | 4) return 1 ;;
  2)
    echo "❌ Failed to inspect a dependency manifest: jq could not read its input (exit 2)" >&2
    exit 2
    ;;
  3)
    echo "❌ Failed to inspect a dependency manifest: jq could not compile its filter (exit 3)" >&2
    exit 3
    ;;
  5)
    echo "❌ Failed to inspect a dependency manifest: jq rejected malformed input (exit 5)" >&2
    exit 5
    ;;
  *)
    echo "❌ Failed to inspect a dependency manifest: unexpected jq exit ${status}" >&2
    exit "${status}"
    ;;
  esac
}

# ### dart-lib-pub-root-uri
# #### source: dart-lib
# Dart package_config rootUri values are URIs, not paths. Hosted packages use
# absolute file:/// URIs, while workspace packages normally use paths relative
# to .dart_tool/package_config.json. Decode URI escapes before asking realpath
# to normalize the resulting filesystem path.
decode_uri_path() {
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

resolve_pub_root() {
  local root_uri=$1
  local package_path

  case "${root_uri}" in
  file://localhost/*) package_path="/${root_uri#file://localhost/}" ;;
  file:///*) package_path="${root_uri#file://}" ;;
  file://*)
    echo "❌ Unsupported authority in Dart package root URI: ${root_uri}" >&2
    return 1
    ;;
  /*) package_path="${root_uri}" ;;
  *) package_path=".dart_tool/${root_uri}" ;;
  esac

  if [[ ${package_path} == *%* ]]; then
    package_path="$(decode_uri_path "${package_path}")" || return 1
  fi
  realpath -m -- "${package_path}"
}

if [ -f package.json ]; then
  jq empty package.json
  if jq_match '
      [
        (.dependencies // {}),
        (.devDependencies // {}),
        (.optionalDependencies // {}),
        (.peerDependencies // {})
      ]
      | add
      | keys[]
      | select(startswith("@atomicloud/diene."))
    ' package.json; then
    node_declared=true
  fi
fi

# rg answers 1 for "no match" and 2 or more for a real failure; a broken scan
# must never be read as "nothing is declared".
if [ -f bun.lock ]; then
  bun_status=0
  rg -q '^[[:space:]]*"@atomicloud/diene\.' bun.lock || bun_status=$?
  if [ "${bun_status}" -ge 2 ]; then
    echo "❌ Failed to scan bun.lock for diene packages (rg exit ${bun_status})" >&2
    exit "${bun_status}"
  fi
  if [ "${bun_status}" -eq 0 ]; then
    node_declared=true
  fi
fi

for package_dir in node_modules/@atomicloud/diene.*; do
  [ -d "${package_dir}" ] || continue
  package="$(basename "${package_dir}")"
  skills_dir="${package_dir}/skills"
  [ -d "${skills_dir}" ] || continue
  [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || continue
  mkdir -p "${staging}/${package}"
  cp -R "${skills_dir}/." "${staging}/${package}/"
  node_staged=true
done

if [ -f Directory.Packages.props ]; then
  nuget_matches="${resolver_dir}/nuget-matches.txt"
  nuget_packages="${resolver_dir}/nuget-packages.tsv"
  nuget_status=0
  rg -o 'PackageVersion Include="AtomiCloud\.Diene\.[^"]+" Version="[^"]+"' Directory.Packages.props \
    >"${nuget_matches}" || nuget_status=$?
  if [ "${nuget_status}" -ge 2 ]; then
    echo "❌ Failed to scan Directory.Packages.props for diene packages (rg exit ${nuget_status})" >&2
    exit "${nuget_status}"
  fi
  sed -E 's/PackageVersion Include="([^"]+)" Version="([^"]+)"/\1\t\2/' "${nuget_matches}" >"${nuget_packages}"
  while IFS=$'\t' read -r package version; do
    [ -n "${package}" ] || continue
    nuget_declared=true
    cache_id="$(echo "${package}" | tr '[:upper:]' '[:lower:]')"
    package_dir="${HOME}/.nuget/packages/${cache_id}/${version}"
    [ -d "${package_dir}" ] || continue
    skills_dir="${package_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
    nuget_staged=true
  done <"${nuget_packages}"
fi

if [ -f go.mod ]; then
  if ! command -v go >/dev/null 2>&1; then
    echo "❌ go.mod is present but the go toolchain is not on PATH" >&2
    exit 1
  fi
  go_manifest="${resolver_dir}/go-manifest.json"
  go_modules="${resolver_dir}/go-modules.json"
  go_entries="${resolver_dir}/go-entries.tsv"

  if ! go mod edit -json >"${go_manifest}"; then
    echo "❌ Failed to read the Go module manifest (go mod edit -json)" >&2
    exit 1
  fi

  go_declares_external=false
  if jq_match 'any(.Require[]?; .Path | test("(^|/)diene[._-]"))' "${go_manifest}"; then
    go_declared=true
    go_declares_external=true
  fi

  # A matching main-module name is not a dependency obligation. The repository
  # may contribute its own skills when present, but having none is a legitimate
  # empty result; only external Require entries must resolve to vendored skills.

  if ! go list -m -json all >"${go_modules}"; then
    echo "❌ Failed to list Go modules (go list -m -json all)" >&2
    exit 1
  fi
  if ! jq -r 'select(.Path | test("(^|/)diene[._-]")) | [.Path, .Dir, (.Main // false)] | @tsv' \
    "${go_modules}" >"${go_entries}"; then
    echo "❌ Failed to parse the Go module list with jq" >&2
    exit 1
  fi

  while IFS=$'\t' read -r module module_dir main_module; do
    [ -n "${module_dir}" ] || continue
    skills_dir="${module_dir}/skills"
    [ -d "${skills_dir}" ] || continue
    [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || continue
    package="$(basename "${module}")"
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
    if [ "${main_module}" = false ] || [ "${go_declares_external}" = false ]; then
      go_staged=true
    fi
  done <"${go_entries}"
fi

pub_status=0
rg -q '^(name:[[:space:]]+diene_[[:alnum:]_]+|[[:space:]]+diene_[[:alnum:]_]+[[:space:]]*:)' --glob pubspec.yaml --glob pubspec.lock . ||
  pub_status=$?
if [ "${pub_status}" -ge 2 ]; then
  echo "❌ Failed to scan pubspec manifests for diene packages (rg exit ${pub_status})" >&2
  exit "${pub_status}"
fi
if [ "${pub_status}" -eq 0 ]; then
  pub_declared=true
fi

if [ -f .dart_tool/package_config.json ]; then
  jq empty .dart_tool/package_config.json
  pub_entries="${resolver_dir}/pub-entries.tsv"
  if ! jq -r '.packages[] | select(.name | startswith("diene_")) | [.name, .rootUri] | @tsv' \
    .dart_tool/package_config.json >"${pub_entries}"; then
    echo "❌ Failed to parse .dart_tool/package_config.json with jq" >&2
    exit 1
  fi
  while IFS=$'\t' read -r package root_uri; do
    [ -n "${package}" ] || continue
    if ! package_root="$(resolve_pub_root "${root_uri}")"; then
      echo "❌ Failed to resolve Dart package root for ${package}" >&2
      exit 1
    fi
    [ -d "${package_root}" ] || continue
    skills_dir="${package_root}/skills"
    [ -d "${skills_dir}" ] || continue
    [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || continue
    mkdir -p "${staging}/${package}"
    cp -R "${skills_dir}/." "${staging}/${package}/"
    pub_staged=true
  done <"${pub_entries}"
fi

chmod -R u+w "${staging}"

# The inventory is taken before manifest.json is written so the manifest never
# lists itself; .gitkeep is a placeholder, not vendored skill content.
staged_list="${resolver_dir}/staged-skills.txt"
find "${staging}" -type f ! -name .gitkeep -printf '%P\n' | LC_ALL=C sort >"${staged_list}"
staged_count="$(wc -l <"${staged_list}")"

unresolved_ecosystems=()
if [ "${node_declared}" = true ] && [ "${node_staged}" = false ]; then
  unresolved_ecosystems+=("node")
fi
if [ "${nuget_declared}" = true ] && [ "${nuget_staged}" = false ]; then
  unresolved_ecosystems+=("nuget")
fi
if [ "${go_declared}" = true ] && [ "${go_staged}" = false ]; then
  unresolved_ecosystems+=("go")
fi
if [ "${pub_declared}" = true ] && [ "${pub_staged}" = false ]; then
  unresolved_ecosystems+=("pub")
fi

# ### workspace-vendor-swap
# #### source: workspace
# A declaration that yields no skill content is a cold checkout, not a request
# to replace committed skills with an empty staging tree. Preserving is only
# legitimate when nothing at all resolved and there are real committed skills to
# keep; anything else must fail instead of publishing a partial or empty tree.
if [ "${#unresolved_ecosystems[@]}" -gt 0 ]; then
  committed_skill=""
  if [ -d "${vendor_dir}" ]; then
    tracked_vendor="${resolver_dir}/tracked-vendor.txt"
    if ! git ls-files -- "${vendor_dir}" >"${tracked_vendor}"; then
      echo "❌ Failed to inspect tracked vendored skills (git ls-files)" >&2
      exit 1
    fi
    while IFS= read -r candidate_skill; do
      if [ "${candidate_skill}" = "${vendor_dir}/.gitkeep" ] ||
        [ "${candidate_skill}" = "${vendor_dir}/manifest.json" ]; then
        continue
      fi
      if [ -f "${candidate_skill}" ]; then
        committed_skill="${candidate_skill}"
        break
      fi
    done <"${tracked_vendor}"
  fi
  if [ "${staged_count}" -eq 0 ] && [ -n "${committed_skill}" ]; then
    echo "⏭️ Declared diene packages (${unresolved_ecosystems[*]}) are not installed; keeping the committed vendored skills"
    exit 0
  fi
  echo "❌ Declared diene packages produced no vendored skills: ${unresolved_ecosystems[*]}" >&2
  echo "❌ Refusing to publish an incomplete vendored-skills tree" >&2
  exit 1
fi

jq -R -s 'split("\n") | map(select(length > 0)) | sort' "${staged_list}" >"${staging}/manifest.json"

# ### dart-lib-vendor-transaction
# #### source: dart-lib
# Keep the previous tree at a same-filesystem sibling until the fully populated
# staging tree has been renamed into place. The EXIT trap restores the backup
# if publication fails or is interrupted between the two renames.
mkdir -p "$(dirname "${vendor_dir}")"
swap_dir="$(mktemp -d .claude/skills/.vendor-swap.XXXXXX)"
backup="${swap_dir}/vendor"
if [ -d "${vendor_dir}" ]; then
  chmod -R u+w "${vendor_dir}"
  mv "${vendor_dir}" "${backup}"
fi
mv "${staging}" "${vendor_dir}"
swap_committed=true
if [ -e "${backup}" ]; then
  chmod -R u+w "${backup}" 2>/dev/null || true
  rm -rf "${backup}"
fi
backup=""
rm -rf "${swap_dir}"
swap_dir=""

echo "✅ Vendored skills synchronized"
