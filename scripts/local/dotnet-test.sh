#!/usr/bin/env bash
set -euo pipefail

kind="${1:-}"
mode="${2:-normal}"

[ "${kind}" != "unit" ] && [ "${kind}" != "int" ] && [ "${kind}" != "meta" ] && echo "❌ Usage: dotnet-test.sh <unit|int|meta> [--watch|--coverage]" >&2 && exit 1
[ "${mode}" != "normal" ] && [ "${mode}" != "--watch" ] && [ "${mode}" != "--coverage" ] && echo "❌ Unknown mode '${mode}'" >&2 && exit 1

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
config="${DOTNET_TEST_CONFIG:-$(find "${root}/.config" -maxdepth 1 -name '*.test.yaml' 2>/dev/null | head -n 1)}"
[ ! -f "${config:-/nonexistent}" ] && echo "❌ Test config not found (.config/*.test.yaml)" >&2 && exit 1
! command -v yq >/dev/null && echo "❌ yq is required to read ${config}" >&2 && exit 1
[ "${kind}" = "meta" ] && [ -z "$(find "${root}" -maxdepth 2 -type f -path '*/TestHelper*.csproj' -print -quit)" ] && echo "✅ No TestHelper project; meta tier is inactive" && exit 0

mapfile -t projects < <(yq -r ".coverage.${kind}.projects[]?" "${config}")
minimum="$(yq -er ".coverage.${kind}.minimum // \"\"" "${config}")"
include="$(yq -er ".coverage.${kind}.include // [] | join(\"%2c\")" "${config}")"
exclude="$(yq -er ".coverage.${kind}.exclude // [] | join(\"%2c\")" "${config}")"
results="${root}/TestResults/${kind}"
coverage="${results}/coverage"

[ "${#projects[@]}" -eq 0 ] && echo "❌ Missing .coverage.${kind}.projects entries in ${config}" >&2 && exit 1
[ -z "${minimum}" ] && echo "❌ Missing .coverage.${kind}.minimum in ${config}" >&2 && exit 1
[ -z "${include}" ] && echo "❌ Missing .coverage.${kind}.include in ${config}" >&2 && exit 1
[[ ! ${minimum} =~ ^[0-9]+$ || ${minimum} -gt 100 ]] && echo "❌ ${kind} coverage minimum '${minimum}' must be an integer in [0,100]" >&2 && exit 1

for project_rel in "${projects[@]}"; do
  project="${root}/${project_rel}"
  [[ ${project_rel} != *.csproj || ${project_rel} == /* || ${project_rel} == *..* || ! -f ${project} ]] && echo "❌ ${kind} project '${project_rel}' must be a relative .csproj path" >&2 && exit 1
done

if [ "${mode}" = "--watch" ]; then
  echo "👀 Watching ${kind} tests from ${projects[0]}..."
  exec dotnet watch --project "${root}/${projects[0]}" test -c Release
fi

rm -rf "${results}"
mkdir -p "${results}"
failed=0

if [ "${mode}" = "normal" ]; then
  for project_rel in "${projects[@]}"; do
    project_name="$(basename "${project_rel}" .csproj)"
    echo "🧪 Running ${kind} tests: ${project_rel}"
    set +e
    dotnet test "${root}/${project_rel}" -c Release \
      --logger "trx;LogFileName=${kind}-${project_name}.trx" \
      --results-directory "${results}"
    code=$?
    set -e
    [ "${code}" -ne 0 ] && failed=1
  done
  [ "${failed}" -ne 0 ] && echo "❌ ${kind} tests failed" >&2 && exit 1
  echo "✅ ${kind} tests complete"
  exit 0
fi

mkdir -p "${coverage}"
accumulator="${coverage}/coverage.json"
last_index=$((${#projects[@]} - 1))

for index in "${!projects[@]}"; do
  project_rel="${projects[${index}]}"
  project_name="$(basename "${project_rel}" .csproj)"
  format="json"
  threshold_args=()
  [ "${index}" -eq "${last_index}" ] && format="json%2ccobertura" && threshold_args=(/p:Threshold="${minimum}" /p:ThresholdType=line /p:ThresholdStat=total)
  merge_args=()
  [ -f "${accumulator}" ] && merge_args=(/p:MergeWith="${accumulator}")

  echo "🧪 Running ${kind} coverage: ${project_rel}"
  set +e
  dotnet test "${root}/${project_rel}" -c Release \
    --logger "trx;LogFileName=${kind}-${project_name}.trx" \
    --results-directory "${results}" \
    /p:CollectCoverage=true \
    /p:CoverletOutput="${coverage}/coverage" \
    /p:CoverletOutputFormat="${format}" \
    /p:Include="${include}" \
    /p:Exclude="${exclude}" \
    "${merge_args[@]}" \
    "${threshold_args[@]}"
  code=$?
  set -e
  [ "${code}" -ne 0 ] && failed=1
done

report="${coverage}/coverage.cobertura.xml"
[ "${failed}" -ne 0 ] && echo "❌ ${kind} tests or merged coverage failed" >&2 && exit 1
[ ! -f "${report}" ] && echo "❌ No merged ${kind} coverage report produced" >&2 && exit 1
! command -v xmlstarlet >/dev/null && echo "❌ xmlstarlet is required to validate ${kind} Cobertura coverage" >&2 && exit 1

valid="$(xmlstarlet sel -t -v '/coverage/@lines-valid' "${report}")"
[ "${valid:-0}" -le 0 ] && echo "❌ ${kind} coverage measured zero lines" >&2 && exit 1

packages="$(xmlstarlet sel -t -m '/coverage/packages/package' -v '@name' -o $'\t' -v '@line-rate' -n "${report}")"
[ -z "${packages}" ] && echo "❌ ${kind} coverage contains no packages" >&2 && exit 1

while IFS=$'\t' read -r assembly line_rate; do
  if [ "${kind}" = "unit" ]; then
    [[ ${assembly} =~ ^Lib.*$ || ${assembly} == "AtomiCloud.Diene.Note" ]] || {
      echo "❌ unit coverage escaped its [Lib*]* ledger: ${assembly}" >&2
      exit 1
    }
  elif [ "${kind}" = "int" ]; then
    [[ ${assembly} =~ ^App.*$ ]] || {
      echo "❌ int coverage escaped its [App*]* ledger: ${assembly}" >&2
      exit 1
    }
  else
    [[ ${assembly} =~ [.]TestHelper$ ]] || {
      echo "❌ meta coverage escaped its [*.TestHelper]* ledger: ${assembly}" >&2
      exit 1
    }
  fi

  awk -v rate="${line_rate}" -v minimum="${minimum}" '
    BEGIN {
      if (rate !~ /^[0-9]+([.][0-9]+)?$/) {
        exit 1
      }
      exit !((rate * 100) + 0.0000001 >= minimum)
    }
  ' </dev/null || {
    echo "❌ ${kind} Cobertura package ${assembly} has line-rate ${line_rate}, below ${minimum}%" >&2
    exit 1
  }
done <<<"${packages}"

echo "🔎 Parsed ${kind} Cobertura package scope and per-package line rates"
echo "📦 Merged ${kind} coverage report: ${report}"
echo "✅ ${kind} coverage meets the ${minimum}% minimum"
