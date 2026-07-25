#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ "${mode}" != "wiring" ] && [ "${mode}" != "release-trigger" ] && [ "${mode}" != "release-concurrency" ] && [ "${mode}" != "workflow-names" ] && echo "❌ unsupported workflow validation mode" >&2 && exit 1

if [ "${mode}" = "wiring" ]; then
  while IFS= read -r script; do
    [ -f "${script}" ] || {
      echo "❌ workflow references missing script '${script}'" >&2
      exit 1
    }
    [ -x "${script}" ] || {
      echo "❌ workflow script '${script}' is not executable" >&2
      exit 1
    }
  done < <(rg -o --no-filename 'scripts/(ci|release)/[A-Za-z0-9._-]+[.]sh' .github/workflows | sort -u)

  for orchestrator in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/workflows/release.yaml; do
    while IFS=$'\t' read -r job reusable; do
      if [ -z "${reusable}" ]; then
        [ "${orchestrator}:${job}" != ".github/workflows/cd.yaml:goreleaser" ] && echo "❌ '${orchestrator}' job '${job}' must call a reusable workflow" >&2 && exit 1
        yq -o=json '.jobs.goreleaser.steps' "${orchestrator}" | jq -e '
          any(.[]; (.run // "") | contains("scripts/release/publish.sh"))
        ' >/dev/null || {
          echo "❌ direct GoReleaser job does not call scripts/release/publish.sh" >&2
          exit 1
        }
        continue
      fi
      [[ ${reusable} == ./.github/workflows/* ]] || {
        echo "❌ '${orchestrator}' job '${job}' must call a repository-local reusable workflow" >&2
        exit 1
      }
      target="${reusable#./}"
      [ -f "${target}" ] || {
        echo "❌ '${orchestrator}' references missing reusable workflow '${target}'" >&2
        exit 1
      }
      rg -q 'scripts/(ci|release)/[A-Za-z0-9._-]+[.]sh' "${target}" || {
        echo "❌ reusable workflow '${target}' does not call a repository script entrypoint" >&2
        exit 1
      }
    done < <(yq -r '.jobs | to_entries[] | [.key, (.value.uses // "")] | @tsv' "${orchestrator}")
  done

  # Reusable jobs inherit least-privilege permissions from their callers.
  while IFS= read -r reusable; do
    yq -o=json '.' "${reusable}" | jq -e '[.jobs[] | has("permissions")] | any | not' >/dev/null || {
      echo "❌ reusable workflow '${reusable}' must not declare job permissions" >&2
      exit 1
    }
  done < <(find .github/workflows -maxdepth 1 -type f -name '⚡reusable-*.yaml' | sort)

  # setup-nix owns checkout. A second checkout can discard its prepared state.
  while IFS= read -r workflow; do
    if rg -q 'AtomiCloud/actions[.]setup-nix@' "${workflow}" && rg -q 'actions/checkout@' "${workflow}"; then
      echo "❌ '${workflow}' combines setup-nix with a duplicate checkout" >&2
      exit 1
    fi
  done < <(find .github/workflows -maxdepth 1 -type f | sort)

  # Every first-party reusable caller carries the family secret-forwarding invariant.
  for orchestrator in .github/workflows/ci.yaml .github/workflows/cd.yaml .github/workflows/release.yaml; do
    yq -o=json '.' "${orchestrator}" | jq -e '
      [.jobs[] | select((.uses // "") | startswith("./.github/workflows/")) | .secrets] |
      all(. == "inherit")
    ' >/dev/null || {
      echo "❌ '${orchestrator}' has a first-party reusable call without secrets: inherit" >&2
      exit 1
    }
  done

  # The CLI artifact is uploaded once, then consumed only after the compile job.
  yq -o=json '.' .github/workflows/ci.yaml | jq -e '
    .jobs.sit.needs == "compile" and
    .jobs.smoke.needs == "compile"
  ' >/dev/null
  compile_artifact="$(yq -o=json '.' .github/workflows/⚡reusable-compile.yaml | jq -r '.jobs.compile.steps[] | select((.uses // "") | startswith("actions/upload-artifact@")) | .with.name')"
  [ -n "${compile_artifact}" ] && [ "${compile_artifact}" != "null" ] || {
    echo "❌ compile workflow does not upload its CLI artifact" >&2
    exit 1
  }
  for consumer in .github/workflows/⚡reusable-sit.yaml .github/workflows/⚡reusable-smoke.yaml; do
    [ "$(yq -o=json '.' "${consumer}" | jq -r '.jobs[].steps[] | select((.uses // "") | startswith("actions/download-artifact@")) | .with.name')" = "${compile_artifact}" ] || {
      echo "❌ '${consumer}' does not download compile artifact '${compile_artifact}'" >&2
      exit 1
    }
  done
  yq -o=json '.' .github/workflows/⚡reusable-smoke.yaml | jq -e '
    [.jobs.smoke.steps[] | select((.uses // "") | startswith("actions/checkout@"))][0].with["persist-credentials"] == false and
    [.jobs.smoke.steps[] | select(.name == "Smoke")][0].env.BINARY == "${{ inputs.binary }}" and
    ([.jobs.smoke.steps[] | select(.name == "Smoke")][0].run | contains("${BINARY}"))
  ' >/dev/null || {
    echo "❌ smoke workflow must use a credential-free checkout and route binary input through env" >&2
    exit 1
  }

  echo "✅ Workflow jobs resolve to existing CI scripts"
  exit 0
fi

if [ "${mode}" = "workflow-names" ]; then
  [ "$(yq -r '.name' .github/workflows/ci.yaml)" != "CI" ] && echo "❌ ci.yaml workflow name must be CI" >&2 && exit 1
  [ "$(yq -r '.name' .github/workflows/cd.yaml)" != "CD" ] && echo "❌ cd.yaml workflow name must be CD" >&2 && exit 1
  echo "✅ CI/CD workflow names conform"
  exit 0
fi

if [ "${mode}" = "release-trigger" ]; then
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.workflows == ["CI"]' >/dev/null || {
    echo "❌ release must trigger from CI" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.branches == ["main"]' >/dev/null || {
    echo "❌ release must be limited to main" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.on.workflow_run.types == ["completed"]' >/dev/null || {
    echo "❌ release workflow_run type must be completed" >&2
    exit 1
  }
  yq -o=json .github/workflows/release.yaml | jq -e '.jobs.release.if == "github.event.workflow_run.conclusion == '\''success'\''"' >/dev/null || {
    echo "❌ release job must require CI success" >&2
    exit 1
  }
  echo "✅ Release trigger conforms"
  exit 0
fi

yq -o=json .github/workflows/release.yaml | jq -e '.concurrency.group == "release"' >/dev/null || {
  echo "❌ release concurrency group must be release" >&2
  exit 1
}
echo "✅ Release concurrency conforms"
