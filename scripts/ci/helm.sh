#!/usr/bin/env bash
set -euo pipefail

push="${CI_HELM_PUSH:-false}"
version="${RELEASE_VERSION:-}"
charts="${CHART_PATHS:-${CHART_PATH:-}}"
vendor_task="${CI_HELM_VENDOR_TASK:-helm:vendor}"
config_dir="${CI_HELM_CONFIG_DIR:-files/config}"
config_file="${CI_HELM_CONFIG_FILE:-settings.yaml}"

[ -z "${charts}" ] && echo "❌ neither 'CHART_PATHS' nor 'CHART_PATH' env var is set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOMAIN:-}" ] && echo "❌ 'DOMAIN' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_PASSWORD:-}" ] && echo "❌ 'DOCKER_PASSWORD' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${DOCKER_USER:-}" ] && echo "❌ 'DOCKER_USER' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_BRANCH:-}" ] && echo "❌ 'GITHUB_BRANCH' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_REPO_REF:-}" ] && echo "❌ 'GITHUB_REPO_REF' env var not set" >&2 && exit 1
[ "${push}" = "true" ] && [ -z "${GITHUB_SHA:-}" ] && echo "❌ 'GITHUB_SHA' env var not set" >&2 && exit 1
command -v pls >/dev/null 2>&1 || {
  echo "❌ 'pls' is not on PATH; the vendor step cannot run" >&2
  exit 1
}

# R20 ships TWO charts — the runtime app chart and the primordial CR chart. They are
# validated and published by ONE invocation so that a single semver reaches both; two
# independent runs could disagree the moment one of them was retried.
read -r -a chart_list <<<"${charts}"
echo "📝 charts under management: ${#chart_list[@]} (${charts})"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# ── vendor the out-of-chart sources IN, before anything reads a chart ────────────────
# Helm resolves `.Files.Get` relative to the chart directory and refuses to look outside
# it, so the app's config YAMLs and the observability tree are copied in at build time.
# Skipping this step does not fail anything: it publishes charts whose ConfigMaps render
# EMPTY while every job stays green. A missing vendor task is therefore an ERROR, never a
# skip — that is the whole point of looking it up instead of calling it blind.
pls --list-all --json >"${work}/tasks.json" 2>/dev/null || {
  echo "❌ could not list the task surface; the vendor step cannot be verified" >&2
  exit 1
}
present="$(jq -r --arg t "${vendor_task}" '[.tasks[]? | select(.name == $t)] | length' "${work}/tasks.json")"
if [ "${present}" -ne 1 ]; then
  echo "❌ vendor task '${vendor_task}' is not in the task surface; refusing to package unvendored charts" >&2
  echo "📝 available tasks:" >&2
  jq -r '.tasks[]?.name' "${work}/tasks.json" >&2
  exit 1
fi
echo "🔨 vendoring chart inputs via '${vendor_task}'"
pls "${vendor_task}"

# The vendor task succeeding is not the same claim as its output landing in a chart THIS
# run is publishing. If it copied somewhere else, every per-chart check below would simply
# find no config directory and skip itself — a gate that disables exactly when it matters.
vendored=0
for chart in "${chart_list[@]}"; do
  [ -d "${chart}/${config_dir}" ] && vendored=$((vendored + 1))
done
echo "📝 ${vendored}/${#chart_list[@]} chart(s) carry a vendored '${config_dir}' after the vendor step"
[ "${vendored}" -eq 0 ] && echo "❌ '${vendor_task}' left no '${config_dir}' in any managed chart" >&2 && exit 1

if [ "${push}" = "true" ]; then
  sha="$(echo "${GITHUB_SHA}" | head -c 6)"
  branch="${GITHUB_BRANCH//[._]/-}"
  branch="${branch//\//-}"
  commit_version="${sha}-${branch}"
  helm_version="${version:-v0.0.0-${commit_version}}"
  image_version="${version:-${commit_version}}"
else
  helm_version="0.0.0-ci"
  image_version="0.0.0-ci"
fi

# ONE semver spans the image tag, both chart versions, and both appVersions. Kargo reads
# chart Version == image Tag, so these two values are deliberately the same string.
echo "📝 release version '${helm_version}', app version '${image_version}' for every chart"

packaged=0
for chart in "${chart_list[@]}"; do
  [ ! -d "${chart}" ] && echo "❌ chart path '${chart}' does not exist" >&2 && exit 1
  [ ! -f "${chart}/Chart.yaml" ] && echo "❌ '${chart}' has no Chart.yaml" >&2 && exit 1
  # The release name is the chart's own name, never a literal: a hardcoded name renders a
  # different service than the one being published (R4).
  name="$(yq -r '.name // ""' "${chart}/Chart.yaml")"
  [ -z "${name}" ] && echo "❌ '${chart}/Chart.yaml' declares no name" >&2 && exit 1

  echo "🔨 linting '${name}' from ${chart}"
  helm lint "${chart}"

  [ "${push}" = "true" ] && yq eval ".appVersion = \"${image_version}\"" "${chart}/Chart.yaml" >"${chart}/Chart.yaml.tmp" && mv "${chart}/Chart.yaml.tmp" "${chart}/Chart.yaml"
  helm dependency build "${chart}"
  helm package "${chart}" -u --version "${helm_version}" --app-version "${image_version}" -d "${work}/${name}"

  # ── assert on what actually SHIPS, not on what sits in the source directory ────────
  # The package is re-rendered so every check below sees the tarball a consumer pulls. A
  # .helmignore that excluded the vendored tree would leave the source directory looking
  # perfect and the artifact hollow, and only this render can tell the two apart.
  package="$(find "${work}/${name}" -maxdepth 1 -type f -name '*.tgz' | head -n 1)"
  [ -z "${package}" ] && echo "❌ '${name}' produced no package" >&2 && exit 1
  rendered="${work}/${name}.rendered.yaml"
  helm template "${name}" "${package}" >"${rendered}"

  # `yq ea` collects ACROSS documents into one array. Per-document `yq` would interleave a
  # literal `---` between every result, which inflates any `wc -l` count and corrupts any
  # name list — a manifest of 8 resources reads back as 15.
  resources="$(yq ea -r '[select(.kind != null)] | length' "${rendered}")"
  maps="$(yq ea -r '[select(.kind == "ConfigMap") | .metadata.name] | join(" ")' "${rendered}")"
  keys="$(yq ea -r '[select(.kind == "ConfigMap") | (.data // {}) | keys | .[]] | join(" ")' "${rendered}")"
  echo "📦 $(basename "${package}") renders ${resources} resource(s)"
  echo "📝 '${name}' ConfigMaps: ${maps:-(none)}"
  echo "📝 '${name}' ConfigMap keys: ${keys:-(none)}"

  # Every chart must render something. The primordial chart legitimately renders no
  # ConfigMap at all, so its floor is the resource count, not a ConfigMap count.
  [ "${resources}" -eq 0 ] && echo "❌ packaged chart '${name}' renders no resources" >&2 && exit 1

  # An empty ConfigMap is never correct — it is what `.Files.Get` produces when the file
  # it was pointed at is not inside the chart.
  hollow="$(yq ea -r '[select(.kind == "ConfigMap") | select((.data // {}) | length == 0) | .metadata.name] | join(" ")' "${rendered}")"
  [ -n "${hollow}" ] && echo "❌ packaged chart '${name}' ships ConfigMap(s) with empty data: ${hollow}" >&2 && exit 1

  # Non-empty is still not enough: a ConfigMap carrying some stray file would pass. Only a
  # chart that actually has a vendored config tree is held to this, so the primordial chart
  # — which correctly renders ZERO ConfigMaps — is not failed for the absence of one. The
  # count assertion above is what stops this branch from being skipped wholesale.
  if [ -d "${chart}/${config_dir}" ]; then
    carriers="$(yq ea -r "[select(.kind == \"ConfigMap\") | select((.data // {}) | has(\"${config_file}\")) | .metadata.name] | join(\" \")" "${rendered}")"
    echo "📝 '${name}' ConfigMaps carrying '${config_file}': ${carriers:-(none)}"
    [ -z "${carriers}" ] && echo "❌ packaged chart '${name}' has ${chart}/${config_dir} but no ConfigMap carries '${config_file}'" >&2 && exit 1
  fi

  packaged=$((packaged + 1))
done

echo "📝 packaged and verified ${packaged}/${#chart_list[@]} chart(s)"
[ "${packaged}" -ne "${#chart_list[@]}" ] && echo "❌ not every chart was packaged" >&2 && exit 1

if [ "${push}" = "true" ]; then
  oci_ref="$(echo "oci://${DOMAIN}/${GITHUB_REPO_REF}" | tr '[:upper:]' '[:lower:]')"
  echo "🔐 logging in to ${DOMAIN}"
  echo "${DOCKER_PASSWORD}" | helm registry login "${DOMAIN}" -u "${DOCKER_USER}" --password-stdin

  pushed=0
  for filename in "${work}"/*/*.tgz; do
    echo "📤 pushing $(basename "${filename}") to ${oci_ref}"
    helm push "${filename}" "${oci_ref}"
    pushed=$((pushed + 1))
  done

  echo "📦 pushed ${pushed} package(s) at version ${helm_version} (appVersion ${image_version})"
  [ "${pushed}" -ne "${packaged}" ] && echo "❌ pushed ${pushed} package(s) for ${packaged} chart(s)" >&2 && exit 1
fi

echo "✅ Helm validation complete for ${packaged} chart(s)"
