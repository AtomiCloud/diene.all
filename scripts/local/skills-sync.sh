#!/usr/bin/env bash
set -euo pipefail

vendor_dir=".claude/skills/vendor"
staging="$(mktemp -d .claude/skills/.vendor.XXXXXX)"
resolver_dir="$(mktemp -d)"
cleanup() {
  if [ -d "${staging}" ]; then
    chmod -R u+w "${staging}" 2>/dev/null || true
    rm -rf "${staging}"
  fi
  rm -rf "${resolver_dir}"
}
trap cleanup EXIT

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

# `jq empty` is a syntax gate whose own parse error names a byte offset but not
# the manifest's role in this sync, so a bare failure reads as an unexplained jq
# crash. The diagnostic supplies that context; the exit status stays jq's own so
# callers keep distinguishing an unreadable file from malformed content.
require_json() {
  local file="$1" role="$2" status=0
  jq empty "${file}" || status=$?
  if [ "${status}" -ne 0 ]; then
    echo "❌ Failed to inspect ${role}: ${file} is not valid JSON (jq exit ${status})" >&2
    exit "${status}"
  fi
}

# Every ecosystem stages the same way: a package contributes only when it ships a
# non-empty skills directory. Answers 0 when content was staged and 1 when there
# is nothing to stage, so each caller keeps owning its own resolved flag. A copy
# that fails is a hard stop, never a silent "nothing to stage".
stage_skills() {
  local root="$1" package="$2"
  local skills_dir="${root}/skills"
  [ -d "${skills_dir}" ] || return 1
  [ -n "$(find "${skills_dir}" -type f -print -quit)" ] || return 1
  if ! mkdir -p "${staging}/${package}"; then
    echo "❌ Failed to create the staging directory for ${package}" >&2
    exit 1
  fi
  if ! cp -R "${skills_dir}/." "${staging}/${package}/"; then
    echo "❌ Failed to stage the skills shipped by ${package}" >&2
    exit 1
  fi
  return 0
}

if [ -f package.json ]; then
  require_json package.json "the Node dependency manifest"
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
  if stage_skills "${package_dir}" "${package}"; then
    node_staged=true
  fi
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

  # A declared package that is NOT installed is recorded, not skipped. The
  # cold-checkout guard below is per-ECOSYSTEM, so a cache holding only SOME of the
  # declared packages leaves nuget_staged true and publishes a PARTIAL vendor tree —
  # exactly the outcome that guard exists to prevent. The freshness gate then fails
  # on a diff that names the missing skills but not the reason, which is how a
  # partially warm runner cache reads as a content defect.
  nuget_absent=()
  while IFS=$'\t' read -r package version; do
    [ -n "${package}" ] || continue
    nuget_declared=true
    cache_id="$(echo "${package}" | tr '[:upper:]' '[:lower:]')"
    package_dir="${HOME}/.nuget/packages/${cache_id}/${version}"
    if [ ! -d "${package_dir}" ]; then
      nuget_absent+=("${package} ${version}")
      continue
    fi
    if stage_skills "${package_dir}" "${package}"; then
      nuget_staged=true
    fi
  done <"${nuget_packages}"

  if [ "${nuget_staged}" = true ] && [ "${#nuget_absent[@]}" -gt 0 ]; then
    echo "❌ Declared diene packages are not installed, so the vendored tree would be partial:" >&2
    printf '   - %s\n' "${nuget_absent[@]}" >&2
    echo "   Run 'dotnet restore' before synchronizing skills." >&2
    exit 1
  fi
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

  # A matching main-module name is not a dependency obligation. The repository
  # may contribute its own skills when present, but having none is a legitimate
  # empty result; only external Require entries must resolve to vendored skills.
  #
  # Every matching Require path is recorded individually rather than collapsed
  # into a single "the Go ecosystem declared something" flag: one requirement
  # that stages skills must not answer for a sibling that never resolved, or two
  # direct requirements where only one appears in `go list -m all` would publish
  # a tree missing half the skills that were required.
  go_required="${resolver_dir}/go-required.txt"
  if ! jq -r '.Require[]?.Path | select(test("(^|/)diene[._-]"))' "${go_manifest}" |
    LC_ALL=C sort -u >"${go_required}"; then
    echo "❌ Failed to parse the Go module manifest with jq" >&2
    exit 1
  fi
  if [ -s "${go_required}" ]; then
    go_declared=true
  fi

  # `go list -m all` walks the WHOLE module graph, so a matching module can appear
  # there transitively without the root go.mod requiring it. Membership in the root
  # Require list is therefore recorded per module: only a directly required module
  # can answer the declaration above, otherwise an unrelated transitive module
  # would mask a direct dependency that never resolved. The module under
  # inspection is bound before `any(...)` because inside the condition `.` is the
  # required path, not the module object.

  if ! go list -m -json all >"${go_modules}"; then
    echo "❌ Failed to list Go modules (go list -m -json all)" >&2
    exit 1
  fi
  if ! jq -r --slurpfile manifest "${go_manifest}" '
      [$manifest[0].Require[]?.Path] as $required
      | . as $module
      | select(($module.Path | test("(^|/)diene[._-]")) and ($module.Main != true))
      | [$module.Path, $module.Dir, any($required[]?; . == $module.Path)]
      | @tsv
    ' "${go_modules}" >"${go_entries}"; then
    echo "❌ Failed to parse the Go module list with jq" >&2
    exit 1
  fi

  go_satisfied="${resolver_dir}/go-satisfied.txt"
  : >"${go_satisfied}"
  while IFS=$'\t' read -r module module_dir directly_required; do
    [ -n "${module_dir}" ] || continue
    package="$(basename "${module}")"
    if stage_skills "${module_dir}" "${package}"; then
      if [ "${directly_required}" = true ]; then
        printf '%s\n' "${module}" >>"${go_satisfied}"
      fi
    fi
  done <"${go_entries}"
  LC_ALL=C sort -u -o "${go_satisfied}" "${go_satisfied}"

  # The ecosystem resolved only when EVERY direct requirement staged skills of
  # its own; requiring a non-empty satisfied set keeps "declared" and "staged"
  # answering the same question, so a manifest with no matching Require entries
  # never reports a vacuous success.
  go_unresolved="${resolver_dir}/go-unresolved.txt"
  LC_ALL=C comm -23 "${go_required}" "${go_satisfied}" >"${go_unresolved}"
  if [ -s "${go_satisfied}" ] && [ ! -s "${go_unresolved}" ]; then
    go_staged=true
  fi

  # A PARTIALLY resolved graph is a hard stop, not a cold checkout: skills did
  # stage, so the module cache is warm and the tree would silently omit the rest.
  # The per-ecosystem guard below only distinguishes "nothing resolved", so it
  # would either preserve the committed tree or refuse without naming the
  # modules at fault.
  if [ -s "${go_satisfied}" ] && [ -s "${go_unresolved}" ]; then
    echo "❌ Directly required diene modules produced no vendored skills, so the vendored tree would be partial:" >&2
    sed 's/^/   - /' "${go_unresolved}" >&2
    echo "   Run 'go mod download' before synchronizing skills." >&2
    exit 1
  fi
fi

# A matching package name is not a dependency obligation. Parse the dependency
# MAPS rather than pattern-matching the file: a prefix match over a manifest
# cannot distinguish a package from its dependencies, so a package named
# `diene_<x>` would otherwise declare ITSELF and never resolve.
#
# Every pubspec.yaml in the tree is read, not only the root one. A pub
# workspace keeps its real dependencies in packages/<name>/pubspec.yaml while
# the root carries only a `workspace:` member list, so a root-only parse sees
# no dependencies on exactly the nodes that have them.
pub_manifests="${resolver_dir}/pub-manifests.txt"
find . -name pubspec.yaml -type f -not -path '*/.dart_tool/*' -print >"${pub_manifests}"
pub_deps="${resolver_dir}/pub-deps.txt"
: >"${pub_deps}"
while IFS= read -r pub_manifest; do
  [ -n "${pub_manifest}" ] || continue
  # `test("^diene_")` is a real prefix match. `== "diene_*"` was a literal string
  # comparison — no dependency is ever named with a trailing asterisk, so it
  # matched nothing and every declared Pub package silently bypassed the
  # unresolved-ecosystem refusal below. yq's expression lexer has no
  # `startswith`, so the anchored regex is the prefix test here.
  if ! yq -r '
    [(.dependencies // {}), (.dev_dependencies // {}), (.dependency_overrides // {})]
    | .[] | keys | .[] | select(test("^diene_"))
  ' "${pub_manifest}" >>"${pub_deps}"; then
    echo "❌ Failed to parse ${pub_manifest} dependency maps with yq" >&2
    exit 1
  fi
done <"${pub_manifests}"
if [ -s "${pub_deps}" ]; then
  pub_declared=true
fi

if [ -f .dart_tool/package_config.json ]; then
  require_json .dart_tool/package_config.json "the resolved Pub package configuration"
  pub_entries="${resolver_dir}/pub-entries.tsv"
  if ! jq -r '.packages[] | select(.name | startswith("diene_")) | [.name, .rootUri] | @tsv' \
    .dart_tool/package_config.json >"${pub_entries}"; then
    echo "❌ Failed to parse .dart_tool/package_config.json with jq" >&2
    exit 1
  fi
  while IFS=$'\t' read -r package root_uri; do
    [ -n "${package}" ] || continue
    case "${root_uri}" in
    file://*) package_root="$(realpath -m "${root_uri#file://}")" ;;
    /*) package_root="$(realpath -m "${root_uri}")" ;;
    *) package_root="$(realpath -m ".dart_tool/${root_uri}")" ;;
    esac
    [ -d "${package_root}" ] || continue
    if stage_skills "${package_root}" "${package}"; then
      pub_staged=true
    fi
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

if [ -d "${vendor_dir}" ]; then
  chmod -R u+w "${vendor_dir}"
fi
rm -rf "${vendor_dir}"
mkdir -p "$(dirname "${vendor_dir}")"
mv "${staging}" "${vendor_dir}"

echo "✅ Vendored skills synchronized"
