#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/../.." && pwd)"
validation_dir="${root}/scripts/validate/fleet-sit"
script_path="${root}/scripts/ci/fleet-sit.sh"

# shellcheck source=scripts/validate/fleet-sit/pins.env
source "${validation_dir}/pins.env"
# shellcheck source=scripts/validate/fleet-sit/assert.sh
source "${validation_dir}/assert.sh"

mode='full'
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [--prepare-only]" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  case "$1" in
  --prepare-only) mode='prepare' ;;
  --full) mode='full' ;;
  *)
    echo "usage: $0 [--prepare-only]" >&2
    exit 2
    ;;
  esac
fi

cd "${root}"

# Keep the hard deadline outside the stateful worker so TERM still runs the
# worker's evidence and cleanup traps.
if [ "${mode}" = 'full' ] && [ "${FLEET_SIT_UNDER_TIMEOUT:-0}" != '1' ]; then
  export FLEET_SIT_UNDER_TIMEOUT=1
  exec timeout --signal=TERM --kill-after=30s 1500 "${script_path}" --full
fi

work=''
report=''
cluster_name=''
cluster_created=0
report_active=0
cleanup_started=0
GIT_SERVER_PID=''
PF_SERVER_PID=''
PF_APPSET_PID=''
GIT_SERVER_PORT=''
PF_SERVER_PORT=''
PF_APPSET_PORT=''
FLEET_REPO_URL=''
FLEET_SERVICES_REPO_URL=''
CANARY_REPO_URL=''
SITOTHER_REPO_URL=''
SIT_SECRET=''
FLEET_SOURCE=''
FLEET_BARE=''
FLEET_LAST_COMMIT=''
COMMIT_SEQUENCE=1
IMPLEMENTATION_SHA256=''
IMPLEMENTATION_FILE_COUNT=''
SIT_SOURCE_HEAD=''

validate_inputs() {
  local command
  for command in bash bun curl git helm jq k3d kubectl rg sha256sum timeout yq; do
    sit_require_command "${command}"
  done

  [ "${ARGOCD_VERSION}" = 'v3.4.5' ] || sit_fail 'ARGOCD_VERSION must remain v3.4.5'
  [[ ${ARGOCD_SOURCE_COMMIT} =~ ^[0-9a-f]{40}$ ]] || sit_fail 'invalid Argo CD source commit pin'
  [[ ${ARGOCD_MANIFEST_SHA256} =~ ^[0-9a-f]{64}$ ]] || sit_fail 'invalid Argo CD install-manifest checksum'
  [[ ${K3S_IMAGE} =~ @sha256:[0-9a-f]{64}$ ]] || sit_fail 'k3s image must use an immutable digest'
  [[ ${ARGOCD_MANIFEST_URL} == *"/${ARGOCD_VERSION}/manifests/install.yaml" ]] ||
    sit_fail 'Argo CD manifest URL and version pin disagree'
  [ -f registry/platforms-appset.yaml ] || sit_fail 'registry/platforms-appset.yaml is missing'
  [ -f registry/argocd-webhook-secret.yaml ] || sit_fail 'registry/argocd-webhook-secret.yaml is missing'
  [ -d registry/charts/diene-platform ] || sit_fail 'diene-platform compiler chart is missing'
}

write_implementation_inventory() {
  local output="$1"
  local paths="${output}.paths.$$"
  {
    printf '%s\n' 'scripts/ci/fleet-sit.sh'
    find scripts/validate/fleet-sit -type f -print
  } | LC_ALL=C sort >"${paths}"
  : >"${output}"
  local path
  while IFS= read -r path; do
    [ -f "${path}" ] || sit_fail "implementation inventory contains a non-regular file: ${path}"
    sha256sum -- "${path}" >>"${output}"
  done <"${paths}"
  rm -f "${paths}"
  IMPLEMENTATION_SHA256="$(sha256sum -- "${output}" | awk '{print $1}')"
  IMPLEMENTATION_FILE_COUNT="$(wc -l <"${output}" | tr -d ' ')"
  [[ ${IMPLEMENTATION_SHA256} =~ ^[0-9a-f]{64}$ ]] || sit_fail 'could not digest implementation inventory'
  [ "${IMPLEMENTATION_FILE_COUNT}" -gt 1 ] || sit_fail 'implementation inventory is unexpectedly small'
}

implementation_uncommitted() {
  if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

assert_clean_unchanged_source() {
  local expected_head="$1"
  local actual_head
  actual_head="$(git rev-parse HEAD)"
  [ "${actual_head}" = "${expected_head}" ] ||
    sit_fail "source HEAD changed during SIT: expected ${expected_head}, found ${actual_head}"
  if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
    git status --short >&2
    sit_fail 'full SIT requires a clean worktree so every consumed byte belongs to the recorded commit'
  fi
}

require_empty_report_directory() {
  local directory="$1"
  if [ -L "${directory}" ]; then
    sit_fail "SIT report path must not be a symlink: ${directory}"
    return 1
  fi
  if [ -e "${directory}" ] && [ ! -d "${directory}" ]; then
    sit_fail "SIT report path exists and is not a directory: ${directory}"
    return 1
  fi
  if [ -d "${directory}" ] && [ -n "$(find "${directory}" -mindepth 1 -print -quit)" ]; then
    sit_fail "SIT report directory must be absent or empty; preserve prior evidence elsewhere: ${directory}"
    return 1
  fi
}

git_commit_at() {
  local repo="$1"
  local message="$2"
  local sequence="$3"
  local stamp
  stamp="$(printf '2026-01-01T00:00:%02dZ' "${sequence}")"
  GIT_AUTHOR_NAME='fleet-sit' \
    GIT_AUTHOR_EMAIL='fleet-sit@invalid.example' \
    GIT_AUTHOR_DATE="${stamp}" \
    GIT_COMMITTER_NAME='fleet-sit' \
    GIT_COMMITTER_EMAIL='fleet-sit@invalid.example' \
    GIT_COMMITTER_DATE="${stamp}" \
    git -C "${repo}" commit --quiet -m "${message}"
}

make_bare_remote() {
  local source_repo="$1"
  local bare_repo="$2"
  git clone --quiet --bare "${source_repo}" "${bare_repo}"
  git -C "${source_repo}" remote add sit "${bare_repo}"
}

prepare_repositories() {
  local src_root="${work}/src"
  local repos_root="${work}/repos"
  mkdir -p "${src_root}" "${repos_root}"

  FLEET_SOURCE="${src_root}/fleet"
  FLEET_BARE="${repos_root}/fleet.git"
  mkdir -p \
    "${FLEET_SOURCE}/registry/charts" \
    "${FLEET_SOURCE}/platforms" \
    "${FLEET_SOURCE}/platforms/sitother/landscapes/pichu"
  cp -R registry/charts/diene-platform "${FLEET_SOURCE}/registry/charts/diene-platform"
  local mirror_schema="${FLEET_SOURCE}/registry/charts/diene-platform/values.schema.json"
  cp "${mirror_schema}" "${work}/values.schema.before.json"
  jq -e '.properties.fleet.properties.repoURL.pattern == "^https://"' "${mirror_schema}" >/dev/null
  sed -i '0,/"pattern": "\^https:\/\/"/s//"pattern": "^https?:\/\/"/' "${mirror_schema}"
  jq -e '
    .properties.fleet.properties.repoURL.pattern == "^https?://" and
    .properties.primordial.properties.server.pattern == "^https://"
  ' "${mirror_schema}" >/dev/null
  diff -u "${work}/values.schema.before.json" "${mirror_schema}" \
    >"${work}/runtime-chart-schema-relaxation.diff" || true
  [ "$(rg -c '^[+-] *"pattern"' "${work}/runtime-chart-schema-relaxation.diff")" -eq 2 ] ||
    sit_fail 'runtime chart schema correction changed more than the fleet.repoURL pattern'
  cp -R platforms/canary "${FLEET_SOURCE}/platforms/canary"
  cp "${validation_dir}/fixtures/sitother.services.yaml" "${FLEET_SOURCE}/platforms/sitother/services.yaml"
  cp "${validation_dir}/fixtures/sitother-row.yaml" "${FLEET_SOURCE}/platforms/sitother/landscapes/pichu/dummy.yaml"

  git init --quiet --initial-branch=main "${FLEET_SOURCE}"
  git -C "${FLEET_SOURCE}" config core.autocrlf false
  git -C "${FLEET_SOURCE}" config core.filemode false
  git -C "${FLEET_SOURCE}" add registry platforms
  git_commit_at "${FLEET_SOURCE}" 'C1 deterministic fleet fixture' 1
  C1_SHA="$(git -C "${FLEET_SOURCE}" rev-parse HEAD)"
  git -C "${FLEET_SOURCE}" tag machinery-stable "${C1_SHA}"
  make_bare_remote "${FLEET_SOURCE}" "${FLEET_BARE}"
  ln -s 'fleet.git' "${repos_root}/fleet-services.git"
  [ "$(readlink "${repos_root}/fleet-services.git")" = 'fleet.git' ] ||
    sit_fail 'fleet services repository alias does not target fleet.git'

  local carbon platform
  for platform in canary sitother; do
    carbon="${src_root}/${platform}.carbon"
    mkdir -p "${carbon}"
    if [ "${platform}" = 'canary' ]; then
      cp registry/charts/diene-platform/tests/fixtures/canary.platform.yaml "${carbon}/platform.yaml"
    else
      yq '(.. | select(tag == "!!str")) |= sub("canary", "sitother")' \
        registry/charts/diene-platform/tests/fixtures/canary.platform.yaml >"${carbon}/platform.yaml"
    fi
    git init --quiet --initial-branch=main "${carbon}"
    git -C "${carbon}" config core.autocrlf false
    git -C "${carbon}" config core.filemode false
    git -C "${carbon}" add platform.yaml
    git_commit_at "${carbon}" "${platform} carbon fixture" 1
    make_bare_remote "${carbon}" "${repos_root}/${platform}.carbon.git"
  done
}

check_git_server_started() {
  kill -0 "${GIT_SERVER_PID}" 2>/dev/null || return 1
  jq -e '.port > 0 and .port < 65536' "${GIT_SERVER_STDOUT}" >/dev/null 2>&1 || return 1
}

start_git_server() {
  local evidence_dir="$1"
  GIT_SERVER_STDOUT="${evidence_dir}/git-server.stdout"
  bun "${validation_dir}/git-server.ts" --root "${work}/repos" --port 0 \
    >"${GIT_SERVER_STDOUT}" 2>"${evidence_dir}/git-server.stderr" &
  GIT_SERVER_PID=$!
  sit_wait_for 15 'Bun smart-HTTP git server to bind' check_git_server_started
  GIT_SERVER_PORT="$(jq -r '.port' "${GIT_SERVER_STDOUT}")"
  git ls-remote "http://127.0.0.1:${GIT_SERVER_PORT}/fleet.git" \
    >"${evidence_dir}/git-ls-remote.txt"
  git ls-remote "http://127.0.0.1:${GIT_SERVER_PORT}/fleet-services.git" \
    >"${evidence_dir}/git-services-ls-remote.txt"
  cmp -s "${evidence_dir}/git-ls-remote.txt" "${evidence_dir}/git-services-ls-remote.txt" ||
    sit_fail 'fleet services repository alias advertised different refs from fleet.git'
  jq -n \
    --arg alias 'fleet-services.git' \
    --arg target "$(readlink "${work}/repos/fleet-services.git")" \
    '{alias:$alias,target:$target,sameAdvertisedRefs:true}' \
    >"${evidence_dir}/git-services-alias.json"
  curl --silent --show-error --dump-header "${evidence_dir}/git-smart-http.headers" \
    --output /dev/null \
    "http://127.0.0.1:${GIT_SERVER_PORT}/fleet.git/info/refs?service=git-upload-pack"
  rg -qi '^content-type: application/x-git-upload-pack-advertisement' \
    "${evidence_dir}/git-smart-http.headers" ||
    sit_fail 'git server did not advertise the smart HTTP upload-pack service'

  FLEET_REPO_URL="http://host.k3d.internal:${GIT_SERVER_PORT}/fleet.git"
  FLEET_SERVICES_REPO_URL="http://host.k3d.internal:${GIT_SERVER_PORT}/fleet-services.git"
  CANARY_REPO_URL="http://host.k3d.internal:${GIT_SERVER_PORT}/canary.carbon.git"
  SITOTHER_REPO_URL="http://host.k3d.internal:${GIT_SERVER_PORT}/sitother.carbon.git"
}

fleet_commit() {
  local message="$1"
  local evidence="$2"
  shift 2
  COMMIT_SEQUENCE=$((COMMIT_SEQUENCE + 1))
  {
    git -C "${FLEET_SOURCE}" add -- "$@"
    git_commit_at "${FLEET_SOURCE}" "${message}" "${COMMIT_SEQUENCE}"
    git -C "${FLEET_SOURCE}" push --quiet sit main
    git -C "${FLEET_SOURCE}" show --stat --oneline --decorate=short HEAD
    git -C "${FLEET_SOURCE}" show --format= --name-only HEAD
  } >"${evidence}" 2>&1
  FLEET_LAST_COMMIT="$(git -C "${FLEET_SOURCE}" rev-parse HEAD)"
}

check_port_forward() {
  local pid="$1"
  local log="$2"
  kill -0 "${pid}" 2>/dev/null || return 1
  rg -q 'Forwarding from 127\.0\.0\.1:[0-9]+' "${log}" 2>/dev/null
}

port_from_log() {
  rg -o 'Forwarding from 127\.0\.0\.1:[0-9]+' "$1" | head -n1 | sed 's/.*://'
}

check_webhook_endpoint() {
  local port="$1"
  local status
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --max-time 3 "http://127.0.0.1:${port}/api/webhook" || true)"
  case "${status}" in
  200 | 400 | 405) return 0 ;;
  *) return 1 ;;
  esac
}

start_port_forwards() {
  local server_log="${report}/port-forward-server.log"
  local appset_log="${report}/port-forward-appset.log"
  kubectl -n argocd port-forward --address 127.0.0.1 service/argocd-server :80 \
    >"${server_log}" 2>&1 &
  PF_SERVER_PID=$!
  kubectl -n argocd port-forward --address 127.0.0.1 service/argocd-applicationset-controller :7000 \
    >"${appset_log}" 2>&1 &
  PF_APPSET_PID=$!
  sit_wait_for 20 'argocd-server port-forward' check_port_forward "${PF_SERVER_PID}" "${server_log}"
  sit_wait_for 20 'ApplicationSet webhook port-forward' check_port_forward "${PF_APPSET_PID}" "${appset_log}"
  PF_SERVER_PORT="$(port_from_log "${server_log}")"
  PF_APPSET_PORT="$(port_from_log "${appset_log}")"
  sit_wait_for 20 'argocd-server webhook endpoint' check_webhook_endpoint "${PF_SERVER_PORT}"
  sit_wait_for 20 'ApplicationSet webhook endpoint' check_webhook_endpoint "${PF_APPSET_PORT}"
}

wait_argo_rollouts() {
  local resource
  while IFS= read -r resource; do
    kubectl -n argocd rollout status "${resource}" --timeout=300s
  done < <(kubectl -n argocd get deployments -o name | sort)
  while IFS= read -r resource; do
    kubectl -n argocd rollout status "${resource}" --timeout=300s
  done < <(kubectl -n argocd get statefulsets -o name | sort)
}

configure_clocks() {
  local interval="$1"
  kubectl -n argocd patch configmap argocd-cm --type merge \
    -p "$(jq -cn --arg interval "${interval}" '{data:{"timeout.reconciliation":$interval,"timeout.reconciliation.jitter":"0s"}}')"
  kubectl -n argocd set env deployment/argocd-applicationset-controller \
    "ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER=${interval}"
  kubectl -n argocd rollout restart deployment/argocd-applicationset-controller
  kubectl -n argocd rollout restart deployment/argocd-repo-server
  kubectl -n argocd rollout restart statefulset/argocd-application-controller
  wait_argo_rollouts
}

seed_cluster_secrets() {
  local tsv="${work}/cluster-inputs.tsv"
  : >"${tsv}"
  local record name landscape label server
  local count=0
  for record in registry/clusters/*.yaml; do
    name="$(yq -r '.metadata.name' "${record}")"
    landscape="$(yq -r '.spec.landscape' "${record}")"
    label="$(yq -r '.metadata.labels["atomi.cloud/landscape"]' "${record}")"
    [ -n "${name}" ] && [ "${name}" != 'null' ] || sit_fail "cluster record has no metadata.name: ${record}"
    [ -n "${landscape}" ] && [ "${landscape}" != 'null' ] || sit_fail "cluster record has no spec.landscape: ${record}"
    [ "${label}" = "${landscape}" ] || sit_fail "cluster record label/spec landscape mismatch: ${record}"
    server="https://${name}.sit.invalid:6443"
    kubectl -n argocd create secret generic "${name}" \
      --from-literal="name=${name}" \
      --from-literal="server=${server}" \
      --from-literal='config={"tlsClientConfig":{"insecure":true}}' \
      --dry-run=client -o yaml |
      LANDSCAPE="${landscape}" yq '
        .metadata.labels."argocd.argoproj.io/secret-type" = "cluster" |
        .metadata.labels."atomi.cloud/landscape" = strenv(LANDSCAPE)
      ' |
      kubectl apply -f -
    printf '%s\t%s\t%s\t%s\n' "${record}" "${name}" "${landscape}" "${server}" >>"${tsv}"
    count=$((count + 1))
  done
  [ "${count}" -eq 4 ] || sit_fail "expected four checked-in cluster records, found ${count}"
  jq -Rn '
    [inputs | split("\t") | {record:.[0],name:.[1],landscape:.[2],server:.[3]}] |
    sort_by(.name)
  ' <"${tsv}" >"${report}/cluster-secret-inputs.json"
}

render_and_apply_appsets() {
  "${validation_dir}/derive-appset.sh" \
    registry/platforms-appset.yaml \
    "${work}/platforms-appset.sit.yaml" \
    "${FLEET_REPO_URL}" \
    "${FLEET_SERVICES_REPO_URL}" \
    "${CANARY_REPO_URL}" \
    "${SITOTHER_REPO_URL}" \
    "${report}"

  helm template canary "${FLEET_SOURCE}/registry/charts/diene-platform" \
    --namespace canary \
    --values "${FLEET_SOURCE}/platforms/canary/services.yaml" \
    --values registry/charts/diene-platform/tests/fixtures/canary.platform.yaml \
    --set-string "fleet.repoURL=${FLEET_REPO_URL}" \
    --set-string 'fleet.revision=main' >"${work}/canary-rendered.yaml"
  yq 'select(.kind == "ApplicationSet")' "${work}/canary-rendered.yaml" >"${work}/canary-appset.yaml"
  yq -e '.kind == "ApplicationSet" and .metadata.name == "canary"' \
    "${work}/canary-appset.yaml" >/dev/null
  cp "${work}/canary-appset.yaml" "${report}/canary-appset.yaml"
  cp "${work}/platforms-appset.sit.yaml" "${report}/platforms-appset.sit.yaml"
  kubectl apply -f "${work}/platforms-appset.sit.yaml"
  kubectl apply -f "${work}/canary-appset.yaml"
}

build_expected_child_apps() {
  local output="$1"
  local tsv="${work}/expected-child-apps.tsv"
  : >"${tsv}"
  local row platform landscape service tag cluster_name_value server matches
  while IFS= read -r row; do
    platform="$(yq -r '.platform' "${row}")"
    landscape="$(yq -r '.landscape' "${row}")"
    service="$(yq -r '.service' "${row}")"
    tag="$(yq -r '.pin.tag' "${row}")"
    printf '%s\t%s\t%s\t%s\n' \
      "${platform}-${landscape}-${service}-primordial" \
      'https://kubernetes.default.svc' "${tag}" "${landscape}" >>"${tsv}"
    matches="$(jq --arg landscape "${landscape}" '[.[] | select(.landscape == $landscape)] | length' \
      "${report}/cluster-secret-inputs.json")"
    [ "${matches}" -eq 1 ] || sit_fail "row ${row} must match exactly one ephemeral cluster Secret"
    cluster_name_value="$(jq -r --arg landscape "${landscape}" '.[] | select(.landscape == $landscape) | .name' \
      "${report}/cluster-secret-inputs.json")"
    server="$(jq -r --arg landscape "${landscape}" '.[] | select(.landscape == $landscape) | .server' \
      "${report}/cluster-secret-inputs.json")"
    printf '%s\t%s\t%s\t%s\n' \
      "${platform}-${landscape}-${service}-${cluster_name_value}" \
      "${server}" "${tag}" "${landscape}" >>"${tsv}"
  done < <(find "${FLEET_SOURCE}/platforms/canary/landscapes" -mindepth 2 -maxdepth 2 -type f -name '*.yaml' | sort)
  jq -Rn '
    [inputs | split("\t") | {name:.[0],server:.[1],targetRevision:.[2],landscape:.[3]}] |
    sort_by(.name)
  ' <"${tsv}" >"${output}"
}

check_baseline_apps() {
  local snapshot="${work}/baseline-check.json"
  local actual="${work}/baseline-actual.json"
  sit_snapshot_apps "${snapshot}" || return 1
  jq '
    [.items[] |
      select(any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "canary")) |
      {name:.metadata.name,server:.spec.destination.server,targetRevision:.spec.sources[0].targetRevision,
       landscape:(.metadata.name | capture("^canary-(?<landscape>[^-]+)-").landscape)}
    ] | sort_by(.name)
  ' "${snapshot}" >"${actual}"
  cmp -s "${report}/expected-child-apps.json" "${actual}" || return 1
  jq -e '
    ([.items[] | select(.metadata.name == "platform-canary" or .metadata.name == "platform-sitother")] | length) == 2 and
    (.items[] | select(.metadata.name == "platform-canary") |
      .spec.sources[0].targetRevision == "main" and .spec.syncPolicy.automated == null) and
    (.items[] | select(.metadata.name == "platform-sitother") |
      .spec.sources[0].targetRevision == "machinery-stable" and
      .spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true)
  ' "${snapshot}" >/dev/null
}

check_child_revision() {
  local landscape="$1"
  local revision="$2"
  kubectl -n argocd get applications.argoproj.io -o json |
    jq -e --arg landscape "${landscape}" --arg revision "${revision}" '
      [.items[] |
        select(any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "canary")) |
        select(.metadata.name | startswith("canary-" + $landscape + "-"))
      ] as $apps |
      ($apps | length) == 2 and all($apps[]; .spec.sources[0].targetRevision == $revision)
    ' >/dev/null 2>&1
}

capture_child_specs() {
  local label="$1"
  sit_snapshot_apps "${report}/apps-${label}.json"
  sit_child_specs "${report}/apps-${label}.json" "${report}/child-specs-${label}.json"
}

expected_changed_names() {
  local output="$1"
  shift
  local landscape name
  local tsv="${work}/changed-names.tsv"
  : >"${tsv}"
  for landscape in "$@"; do
    while IFS= read -r name; do
      printf '%s\n' "${name}" >>"${tsv}"
    done < <(jq -r --arg landscape "${landscape}" '.[] | select(.landscape == $landscape) | .name' \
      "${report}/expected-child-apps.json")
  done
  jq -Rn '[inputs] | sort' <"${tsv}" >"${output}"
}

assert_changed_landscapes() {
  local before="$1"
  local after="$2"
  local label="$3"
  shift 3
  sit_changed_names "${before}" "${after}" "${report}/changed-${label}.json"
  expected_changed_names "${work}/expected-changed-${label}.json" "$@"
  sit_assert_json_equal "${work}/expected-changed-${label}.json" "${report}/changed-${label}.json" \
    "${label} changed an unexpected generated Application spec"
}

send_webhook() {
  local endpoint="$1"
  local signature_mode="$2"
  local output="$3"
  local ref="$4"
  local before="$5"
  local after="$6"
  shift 6
  local args=(
    "${validation_dir}/github-webhook.ts"
    --url "${endpoint}"
    --repo-url "${FLEET_REPO_URL}"
    --secret "${SIT_SECRET}"
    --ref "${ref}"
    --before "${before}"
    --after "${after}"
  )
  local changed
  for changed in "$@"; do
    args+=(--changed "${changed}")
  done
  case "${signature_mode}" in
  correct) ;;
  wrong) args+=(--wrong-secret) ;;
  missing) args+=(--no-signature) ;;
  *) sit_fail "unknown signature mode: ${signature_mode}" ;;
  esac
  bun "${args[@]}" >"${output}"
}

check_platform_source_revision() {
  local application="$1"
  local expected="$2"
  kubectl -n argocd get application.argoproj.io "${application}" -o json |
    jq -e --arg expected "${expected}" '.status.sync.revisions[0] == $expected' >/dev/null 2>&1
}

check_application_controller_replicas() {
  local expected="$1"
  kubectl -n argocd get statefulset argocd-application-controller -o json |
    jq -e --argjson expected "${expected}" '(.status.replicas // 0) == $expected' >/dev/null 2>&1
}

scale_application_controller() {
  local replicas="$1"
  kubectl -n argocd scale statefulset argocd-application-controller --replicas="${replicas}"
  if [ "${replicas}" -eq 0 ]; then
    sit_wait_for 60 'Application controller to stop' check_application_controller_replicas 0
  else
    kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
  fi
}

check_sitother_recreated_without_operation() {
  local old_uid="$1"
  kubectl -n argocd get application.argoproj.io platform-sitother -o json |
    jq -e --arg oldUid "${old_uid}" '
      .metadata.uid != $oldUid and
      .spec.syncPolicy.automated.prune == true and
      .spec.syncPolicy.automated.selfHeal == true and
      .operation == null and
      .status.operationState == null
    ' >/dev/null 2>&1
}

check_sitother_c4_automation_live() {
  local expected_revision="$1"
  local expected_uid="$2"
  local not_before="$3"
  kubectl -n argocd get application.argoproj.io platform-sitother -o json |
    jq -e \
      --arg expected "${expected_revision}" \
      --arg uid "${expected_uid}" \
      --arg notBefore "${not_before}" '
      .metadata.uid == $uid and
      .spec.syncPolicy.automated.prune == true and
      .spec.syncPolicy.automated.selfHeal == true and
      .status.sync.revisions[0] == $expected and
      .operation.initiatedBy.automated == true and
      .operation.sync.revisions[0] == $expected and
      .status.operationState.startedAt >= $notBefore and
      .status.operationState.operation.initiatedBy.automated == true and
      .status.operationState.operation.sync.revisions[0] == $expected
    ' >/dev/null 2>&1
}

collect_final_evidence() {
  [ "${cluster_created}" -eq 1 ] || return 0
  [ -n "${report}" ] || return 0
  kubectl -n argocd get applications.argoproj.io -o json >"${report}/apps-final.json" 2>&1 || true
  kubectl -n argocd get applicationsets.argoproj.io -o yaml >"${report}/appsets-final.yaml" 2>&1 || true
  kubectl -n argocd get pods -o wide >"${report}/pods-final.txt" 2>&1 || true
  kubectl -n argocd get events --sort-by=.lastTimestamp >"${report}/events-final.txt" 2>&1 || true
  local workload
  for workload in \
    deployment/argocd-applicationset-controller \
    deployment/argocd-repo-server \
    deployment/argocd-server \
    statefulset/argocd-application-controller; do
    kubectl -n argocd logs "${workload}" --all-containers --tail=-1 \
      >"${report}/$(tr '/' '-' <<<"${workload}").log" 2>&1 || true
  done
}

stop_pid() {
  local pid="$1"
  if [[ ${pid} =~ ^[0-9]+$ ]]; then
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi
}

cleanup() {
  local rc=$?
  [ "${cleanup_started}" -eq 0 ] || return
  cleanup_started=1
  trap - EXIT ERR TERM INT
  set +e
  collect_final_evidence
  stop_pid "${PF_SERVER_PID}"
  stop_pid "${PF_APPSET_PID}"
  stop_pid "${GIT_SERVER_PID}"
  if [ "${cluster_created}" -eq 1 ] && [ -n "${cluster_name}" ]; then
    k3d cluster delete "${cluster_name}" >"${report}/cluster-delete.log" 2>&1 || true
  fi
  if [ "${report_active}" -eq 1 ] && [ -f "${SIT_REPORT_FILE}" ]; then
    if [ "$(jq -r '.status' "${SIT_REPORT_FILE}" 2>/dev/null)" = 'running' ]; then
      sit_report_finish fail || true
    fi
  fi
  if [[ ${work} == /tmp/* ]] && [ -d "${work}" ]; then
    rm -rf "${work}"
  fi
  exit "${rc}"
}

on_error() {
  local rc=$?
  local line="${BASH_LINENO[0]:-unknown}"
  local command="${BASH_COMMAND:-unknown}"
  trap - ERR
  set +e
  if [ "${report_active}" -eq 1 ]; then
    printf 'exit_code=%s\nline=%s\ncommand=%s\n' "${rc}" "${line}" "${command}" \
      >"${report}/last-error.txt"
    SIT_LEG_EVIDENCE+=('last-error.txt')
    sit_leg_fail "${rc}" "command failed at line ${line}"
    sit_report_finish fail
  fi
  exit "${rc}"
}

prepare_only() {
  validate_inputs
  local prepare_work
  prepare_work="$(mktemp -d)"
  work="${prepare_work}"
  local prepare_report="${prepare_work}/evidence"
  mkdir -p "${prepare_report}"
  trap 'stop_pid "${GIT_SERVER_PID}"; if [[ "${work}" == /tmp/* ]]; then rm -rf "${work}"; fi' EXIT

  write_implementation_inventory "${prepare_report}/implementation-inventory.sha256"

  bun "${validation_dir}/git-server.ts" --root "${prepare_work}" --self-test \
    >"${prepare_report}/git-server-self-test.json"
  bun "${validation_dir}/github-webhook.ts" --self-test \
    >"${prepare_report}/github-webhook-self-test.json"
  bun build "${validation_dir}/git-server.ts" --target=bun --outfile="${prepare_work}/git-server.js" >/dev/null
  bun build "${validation_dir}/github-webhook.ts" --target=bun --outfile="${prepare_work}/github-webhook.js" >/dev/null

  prepare_repositories
  cp "${work}/runtime-chart-schema-relaxation.diff" "${prepare_report}/runtime-chart-schema-relaxation.diff"
  start_git_server "${prepare_report}"
  "${validation_dir}/derive-appset.sh" \
    registry/platforms-appset.yaml \
    "${prepare_work}/platforms-appset.sit.yaml" \
    "${FLEET_REPO_URL}" "${FLEET_SERVICES_REPO_URL}" \
    "${CANARY_REPO_URL}" "${SITOTHER_REPO_URL}" \
    "${prepare_report}"

  helm template canary "${FLEET_SOURCE}/registry/charts/diene-platform" \
    --namespace canary \
    --values "${FLEET_SOURCE}/platforms/canary/services.yaml" \
    --values registry/charts/diene-platform/tests/fixtures/canary.platform.yaml \
    --set-string "fleet.repoURL=${FLEET_REPO_URL}" \
    --set-string 'fleet.revision=main' |
    yq 'select(.kind == "ApplicationSet")' >"${prepare_work}/canary-appset.yaml"
  yq -o=json '.' "${prepare_work}/canary-appset.yaml" |
    jq -e '
      .metadata.name == "canary" and
      .spec.generators[0].git.files[0].path == "platforms/canary/landscapes/*/*.yaml" and
      .spec.generators[1].matrix.generators[0].git.files[0].path == "platforms/canary/landscapes/*/*.yaml" and
      .spec.generators[1].matrix.generators[1].clusters.selector.matchLabels["atomi.cloud/landscape"] == "{{ .landscape }}"
    ' >/dev/null

  sit_report_init "${prepare_work}/report-self-test" \
    "${ARGOCD_VERSION}" "${ARGOCD_SOURCE_COMMIT}" "${ARGOCD_MANIFEST_SHA256}" "${K3S_IMAGE}" \
    "$(git rev-parse HEAD)" "${IMPLEMENTATION_SHA256}" "$(implementation_uncommitted)" \
    "${IMPLEMENTATION_FILE_COUNT}"
  jq -n '{fixture:true}' >"${SIT_REPORT_DIR}/fixture.json"
  sit_leg_begin 'self-test' 'fixture.json'
  sit_leg_pass 'report append helper'
  sit_report_finish pass
  jq -e --arg digest "${IMPLEMENTATION_SHA256}" '
    .status == "pass" and
    .implementationSha256 == $digest and
    (.implementationUncommittedAtProof | type) == "boolean" and
    .legs == [{leg:"self-test",status:"pass",started:.legs[0].started,elapsed_s:.legs[0].elapsed_s,evidence:["fixture.json"],note:"report append helper"}]
  ' \
    "${SIT_REPORT_FILE}" >/dev/null

  jq -n \
    --arg argocd "${ARGOCD_VERSION}" \
    --arg manifestSha256 "${ARGOCD_MANIFEST_SHA256}" \
    --arg k3s "${K3S_IMAGE}" \
    --arg c1 "${C1_SHA}" \
    '{status:"pass",argocd:$argocd,manifestSha256:$manifestSha256,k3s:$k3s,fixtureHead:$c1}' \
    >"${prepare_report}/prepare-only.json"
  echo 'fleet SIT prepare-only checks passed'
}

run_full() {
  validate_inputs
  SIT_SOURCE_HEAD="$(git rev-parse HEAD)"
  assert_clean_unchanged_source "${SIT_SOURCE_HEAD}"
  report="${FLEET_SIT_REPORT:-${root}/sit-report}"
  require_empty_report_directory "${report}"
  work="$(mktemp -d)"
  mkdir -p "${report}"
  write_implementation_inventory "${report}/implementation-inventory.sha256"
  sit_report_init "${report}" \
    "${ARGOCD_VERSION}" "${ARGOCD_SOURCE_COMMIT}" "${ARGOCD_MANIFEST_SHA256}" "${K3S_IMAGE}" \
    "${SIT_SOURCE_HEAD}" "${IMPLEMENTATION_SHA256}" false \
    "${IMPLEMENTATION_FILE_COUNT}"
  report_active=1
  exec > >(tee -a "${report}/harness.log") 2>&1
  trap cleanup EXIT
  trap on_error ERR
  trap 'exit 124' TERM
  trap 'exit 130' INT

  sit_leg_begin 'L0-runtime-setup' \
    'pins-verified.txt' 'manifest-contract.json' 'git-ls-remote.txt' \
    'git-services-ls-remote.txt' 'git-services-alias.json' 'git-smart-http.headers' \
    'platforms-appset.authorized-diff.json' 'canary-appset.yaml' 'cluster-secret-inputs.json' \
    'runtime-chart-schema-relaxation.diff' 'server-http-runtime.json' \
    'implementation-inventory.sha256'
  prepare_repositories
  cp "${work}/runtime-chart-schema-relaxation.diff" "${report}/runtime-chart-schema-relaxation.diff"
  start_git_server "${report}"

  cluster_name="fleet-sit-$$"
  export KUBECONFIG="${work}/kubeconfig"
  k3d cluster create "${cluster_name}" \
    --image "${K3S_IMAGE}" \
    --servers 1 --agents 0 --no-lb --wait --timeout 180s \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false
  cluster_created=1
  k3d kubeconfig get "${cluster_name}" >"${KUBECONFIG}"
  kubectl wait --for=condition=Ready node --all --timeout=120s

  curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
    "${ARGOCD_MANIFEST_URL}" --output "${work}/argocd-install.yaml"
  printf '%s  %s\n' "${ARGOCD_MANIFEST_SHA256}" "${work}/argocd-install.yaml" |
    sha256sum --check | tee "${report}/pins-verified.txt"
  yq eval-all -o=json 'select(.kind == "Service" and .metadata.name == "argocd-applicationset-controller")' \
    "${work}/argocd-install.yaml" |
    jq -e '{applicationSetWebhookPort:.spec.ports[] | select(.name == "webhook") | .port}' \
      >"${report}/manifest-contract.json"
  jq -e '.applicationSetWebhookPort == 7000' "${report}/manifest-contract.json" >/dev/null
  yq eval-all -o=json 'select(.kind == "Service" and .metadata.name == "argocd-server")' \
    "${work}/argocd-install.yaml" |
    jq -e 'any(.spec.ports[]; .name == "http" and .port == 80)' >/dev/null
  yq eval-all -o=json 'select(.kind == "Deployment" and .metadata.name == "argocd-applicationset-controller")' \
    "${work}/argocd-install.yaml" |
    jq -e 'any(.spec.template.spec.containers[0].env[]; .name == "ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER")' >/dev/null

  kubectl create namespace argocd
  kubectl -n argocd apply --server-side --force-conflicts --field-manager=fleet-sit \
    -f "${work}/argocd-install.yaml"
  wait_argo_rollouts

  local webhook_key
  webhook_key="$(yq -r '.spec.data[0].secretKey' registry/argocd-webhook-secret.yaml)"
  [ "${webhook_key}" = 'webhook.github.secret' ] || sit_fail 'committed ESO webhook key changed unexpectedly'
  SIT_SECRET="$(bun -e "console.log(crypto.randomUUID() + crypto.randomUUID())")"
  kubectl -n argocd patch secret argocd-secret --type merge \
    -p "$(jq -cn --arg key "${webhook_key}" --arg secret "${SIT_SECRET}" '{stringData:{($key):$secret}}')"
  configure_clocks '24h'
  kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
    -p '{"data":{"server.insecure":"true"}}' -o json |
    jq '{configMap:.metadata.name,serverInsecure:.data["server.insecure"],webhookTransport:"http"}' \
      >"${report}/server-http-runtime.json"
  jq -e '.configMap == "argocd-cmd-params-cm" and .serverInsecure == "true"' \
    "${report}/server-http-runtime.json" >/dev/null
  kubectl -n argocd rollout restart deployment/argocd-server
  wait_argo_rollouts

  seed_cluster_secrets
  start_port_forwards
  render_and_apply_appsets
  kubectl -n argocd get applicationsets.argoproj.io -o yaml >"${report}/appsets-initial.yaml"
  sit_leg_pass 'pinned Argo CD and k3s are live; webhook clocks are isolated at 24h'

  sit_leg_begin 'L1-baseline-generation' \
    'expected-child-apps.json' 'apps-S0.json' 'child-specs-S0.json' 'appsets-S0.yaml'
  build_expected_child_apps "${report}/expected-child-apps.json"
  sit_wait_for 120 'eight canary row Applications and both platform Applications' check_baseline_apps
  capture_child_specs 'S0'
  kubectl -n argocd get applicationsets.argoproj.io -o yaml >"${report}/appsets-S0.yaml"
  jq -e 'length == 8' "${report}/child-specs-S0.json" >/dev/null
  sit_leg_pass '4 rows x (Primordial + one label-matched cluster Secret), plus committed platform policies'

  local row before_sha
  row="${FLEET_SOURCE}/platforms/canary/landscapes/raichu/dummy.yaml"
  sit_leg_begin 'L2-signed-webhook-one-row' \
    'webhook-L2.json' 'git-C2.txt' 'apps-S2.json' 'child-specs-S2.json' 'changed-L2.json'
  before_sha="$(git -C "${FLEET_SOURCE}" rev-parse HEAD)"
  yq -i '.pin.tag = "0.1.1-sit-l2"' "${row}"
  fleet_commit 'C2 raichu row pin' "${report}/git-C2.txt" 'platforms/canary/landscapes/raichu/dummy.yaml'
  C2_SHA="${FLEET_LAST_COMMIT}"
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" correct \
    "${report}/webhook-L2.json" 'refs/heads/main' "${before_sha}" "${C2_SHA}" \
    'platforms/canary/landscapes/raichu/dummy.yaml'
  sit_assert_http_success "${report}/webhook-L2.json"
  sit_wait_for 90 'signed webhook to update only the raichu row pair' \
    check_child_revision raichu '0.1.1-sit-l2'
  capture_child_specs 'S2'
  assert_changed_landscapes "${report}/child-specs-S0.json" "${report}/child-specs-S2.json" L2 raichu
  sit_leg_pass 'signed GitHub push refreshed one row; every other canary Application spec stayed deep-equal'

  sit_leg_begin 'L3-invalid-signatures-no-refresh' \
    'webhook-L3-wrong.json' 'webhook-L3-missing.json' 'webhook-L3-correct.json' \
    'git-C3.txt' 'apps-L3-negative-end.json' 'apps-S3.json' 'child-specs-S3.json' 'changed-L3.json'
  before_sha="${C2_SHA}"
  row="${FLEET_SOURCE}/platforms/canary/landscapes/pichu/dummy.yaml"
  yq -i '.pin.tag = "0.1.2-sit-l3"' "${row}"
  fleet_commit 'C3 pichu row pin' "${report}/git-C3.txt" 'platforms/canary/landscapes/pichu/dummy.yaml'
  C3_SHA="${FLEET_LAST_COMMIT}"
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" wrong \
    "${report}/webhook-L3-wrong.json" 'refs/heads/main' "${before_sha}" "${C3_SHA}" \
    'platforms/canary/landscapes/pichu/dummy.yaml'
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" missing \
    "${report}/webhook-L3-missing.json" 'refs/heads/main' "${before_sha}" "${C3_SHA}" \
    'platforms/canary/landscapes/pichu/dummy.yaml'
  sit_assert_http_rejected wrong 'HMAC verification failed' "${report}/webhook-L3-wrong.json"
  sit_assert_http_rejected missing 'missing X-Hub-Signature-256' "${report}/webhook-L3-missing.json"
  sit_assert_child_specs_stable_for 90 "${report}/child-specs-S2.json" \
    "${report}/apps-L3-negative-changed.json"
  capture_child_specs 'L3-negative-end'
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" correct \
    "${report}/webhook-L3-correct.json" 'refs/heads/main' "${before_sha}" "${C3_SHA}" \
    'platforms/canary/landscapes/pichu/dummy.yaml'
  sit_assert_http_success "${report}/webhook-L3-correct.json"
  sit_wait_for 90 'proof-of-life signed webhook to update the pichu pair' \
    check_child_revision pichu '0.1.2-sit-l3'
  capture_child_specs 'S3'
  assert_changed_landscapes "${report}/child-specs-S2.json" "${report}/child-specs-S3.json" L3 pichu
  sit_leg_pass 'wrong and missing signatures returned pinned HTTP 400 rejections and caused no refresh for 90s'

  sit_leg_begin 'L4-main-tag-and-manual-policy' \
    'webhook-L4-appset.json' 'webhook-L4-application.json' 'git-C4.txt' \
    'platform-canary-before-L4.json' 'platform-canary-after-L4.json' 'platform-sitother-after-L4.json'
  kubectl -n argocd get application.argoproj.io platform-canary -o json \
    >"${report}/platform-canary-before-L4.json"
  before_sha="${C3_SHA}"
  printf '%s\n' \
    'apiVersion: v1' \
    'kind: ConfigMap' \
    'metadata:' \
    '  name: fleet-sit-compiler-proof' \
    '  namespace: {{ .Release.Namespace }}' \
    '  labels:' \
    '    app.kubernetes.io/part-of: diene-fleet' \
    'data:' \
    '  revision: c4' \
    >"${FLEET_SOURCE}/registry/charts/diene-platform/templates/fleet-sit-proof.yaml"
  fleet_commit 'C4 compiler chart render marker' "${report}/git-C4.txt" \
    'registry/charts/diene-platform/templates/fleet-sit-proof.yaml'
  C4_SHA="${FLEET_LAST_COMMIT}"
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" correct \
    "${report}/webhook-L4-appset.json" 'refs/heads/main' "${before_sha}" "${C4_SHA}" \
    'registry/charts/diene-platform/templates/fleet-sit-proof.yaml'
  send_webhook "http://127.0.0.1:${PF_SERVER_PORT}/api/webhook" correct \
    "${report}/webhook-L4-application.json" 'refs/heads/main' "${before_sha}" "${C4_SHA}" \
    'registry/charts/diene-platform/templates/fleet-sit-proof.yaml'
  sit_assert_http_success "${report}/webhook-L4-appset.json"
  sit_assert_http_success "${report}/webhook-L4-application.json"
  sit_wait_for 120 'platform-canary comparison to resolve C4 on main' \
    check_platform_source_revision platform-canary "${C4_SHA}"
  kubectl -n argocd get application.argoproj.io platform-canary -o json \
    >"${report}/platform-canary-after-L4.json"
  kubectl -n argocd get application.argoproj.io platform-sitother -o json \
    >"${report}/platform-sitother-after-L4.json"
  jq -e --arg c4 "${C4_SHA}" '
    .spec.sources[0].targetRevision == "main" and
    .status.sync.revisions[0] == $c4 and
    .status.sync.status == "OutOfSync" and
    .spec.syncPolicy.automated == null and
    .operation == null and
    .status.operationState == null
  ' "${report}/platform-canary-after-L4.json" >/dev/null
  jq -e --arg c1 "${C1_SHA}" '
    .spec.sources[0].targetRevision == "machinery-stable" and
    .status.sync.revisions[0] == $c1 and
    .spec.syncPolicy.automated.prune == true and
    .spec.syncPolicy.automated.selfHeal == true
  ' "${report}/platform-sitother-after-L4.json" >/dev/null
  sit_leg_pass 'canary main moved to C4 and stayed manual/OutOfSync; sitother source A stayed at machinery-stable C1'

  sit_leg_begin 'L5-machinery-tag-and-automated-policy' \
    'webhook-L5-application.json' 'git-C5-tag.txt' 'l5-reset-and-tag.json' \
    'platform-sitother-before-L5.json' 'platform-sitother-reset-L5.json' \
    'platform-sitother-after-L5.json' 'platform-canary-after-L5.json'
  cp "${report}/platform-sitother-after-L4.json" "${report}/platform-sitother-before-L5.json"
  local previous_uid recreated_uid tag_moved_at
  previous_uid="$(jq -r '.metadata.uid' "${report}/platform-sitother-before-L5.json")"
  [ -n "${previous_uid}" ] && [ "${previous_uid}" != 'null' ] ||
    sit_fail 'platform-sitother had no UID before the L5 reset'
  scale_application_controller 0
  kubectl -n argocd delete application.argoproj.io platform-sitother --wait=true
  sit_wait_for 90 'ApplicationSet controller to recreate platform-sitother without an operation' \
    check_sitother_recreated_without_operation "${previous_uid}"
  kubectl -n argocd get application.argoproj.io platform-sitother -o json \
    >"${report}/platform-sitother-reset-L5.json"
  recreated_uid="$(jq -r '.metadata.uid' "${report}/platform-sitother-reset-L5.json")"
  {
    git -C "${FLEET_SOURCE}" tag --force machinery-stable "${C4_SHA}"
    git -C "${FLEET_SOURCE}" push --quiet --force sit refs/tags/machinery-stable
    git -C "${FLEET_SOURCE}" show-ref --tags machinery-stable
  } >"${report}/git-C5-tag.txt" 2>&1
  tag_moved_at="$(sit_now)"
  jq -n \
    --arg previousUid "${previous_uid}" \
    --arg recreatedUid "${recreated_uid}" \
    --arg tagMovedAt "${tag_moved_at}" \
    --arg c4 "${C4_SHA}" \
    '{previousUid:$previousUid,recreatedUid:$recreatedUid,applicationControllerReplicasDuringReset:0,tagMovedAt:$tagMovedAt,machineryStableRevision:$c4}' \
    >"${report}/l5-reset-and-tag.json"
  send_webhook "http://127.0.0.1:${PF_SERVER_PORT}/api/webhook" correct \
    "${report}/webhook-L5-application.json" 'refs/tags/machinery-stable' "${C1_SHA}" "${C4_SHA}"
  sit_assert_http_success "${report}/webhook-L5-application.json"
  scale_application_controller 1
  sit_wait_for 120 'new post-tag C4 automatic operation on recreated platform-sitother' \
    check_sitother_c4_automation_live "${C4_SHA}" "${recreated_uid}" "${tag_moved_at}"
  kubectl -n argocd get application.argoproj.io platform-sitother -o json \
    >"${report}/platform-sitother-after-L5.json"
  kubectl -n argocd get application.argoproj.io platform-canary -o json \
    >"${report}/platform-canary-after-L5.json"
  jq -e \
    --arg c4 "${C4_SHA}" \
    --arg uid "${recreated_uid}" \
    --arg tagMovedAt "${tag_moved_at}" '
    .metadata.uid == $uid and
    .status.sync.revisions[0] == $c4 and
    .spec.syncPolicy.automated.prune == true and
    .spec.syncPolicy.automated.selfHeal == true and
    .operation.initiatedBy.automated == true and
    .operation.sync.revisions[0] == $c4 and
    .status.operationState.startedAt >= $tagMovedAt and
    .status.operationState.operation.initiatedBy.automated == true and
    .status.operationState.operation.sync.revisions[0] == $c4
  ' "${report}/platform-sitother-after-L5.json" >/dev/null
  jq -e '.operation == null and .status.operationState == null and .spec.syncPolicy.automated == null' \
    "${report}/platform-canary-after-L5.json" >/dev/null
  sit_leg_pass 'after an operation-free UID reset, machinery-stable moved to C4 and the restored controller launched a new automatic C4 operation; canary still had no operation'

  sit_leg_begin 'L6-two-row-union-and-no-row' \
    'webhook-L6-two-row.json' 'webhook-L6-no-row.json' 'git-C6-two-row.txt' 'git-C6-no-row.txt' \
    'apps-S6-two-row.json' 'child-specs-S6-two-row.json' 'changed-L6.json' 'apps-L6-no-row-end.json'
  before_sha="${C4_SHA}"
  yq -i '.pin.tag = "0.1.3-sit-l6"' \
    "${FLEET_SOURCE}/platforms/canary/landscapes/pichu/dummy.yaml"
  yq -i '.pin.tag = "0.1.3-sit-l6"' \
    "${FLEET_SOURCE}/platforms/canary/landscapes/amphoros/dummy.yaml"
  printf '\n# SIT C6 roster-only companion change\n' >>"${FLEET_SOURCE}/platforms/canary/services.yaml"
  fleet_commit 'C6 two rows plus roster comment' "${report}/git-C6-two-row.txt" \
    'platforms/canary/landscapes/pichu/dummy.yaml' \
    'platforms/canary/landscapes/amphoros/dummy.yaml' \
    'platforms/canary/services.yaml'
  C6_SHA="${FLEET_LAST_COMMIT}"
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" correct \
    "${report}/webhook-L6-two-row.json" 'refs/heads/main' "${before_sha}" "${C6_SHA}" \
    'platforms/canary/landscapes/pichu/dummy.yaml' \
    'platforms/canary/landscapes/amphoros/dummy.yaml' \
    'platforms/canary/services.yaml'
  sit_assert_http_success "${report}/webhook-L6-two-row.json"
  sit_wait_for 90 'pichu half of the two-row union' check_child_revision pichu '0.1.3-sit-l6'
  sit_wait_for 90 'amphoros half of the two-row union' check_child_revision amphoros '0.1.3-sit-l6'
  capture_child_specs 'S6-two-row'
  assert_changed_landscapes "${report}/child-specs-S3.json" \
    "${report}/child-specs-S6-two-row.json" L6 pichu amphoros

  before_sha="${C6_SHA}"
  printf '# SIT C6 non-row-only change\n' >>"${FLEET_SOURCE}/platforms/canary/services.yaml"
  fleet_commit 'C6b roster-only no-row path' "${report}/git-C6-no-row.txt" 'platforms/canary/services.yaml'
  C6B_SHA="${FLEET_LAST_COMMIT}"
  send_webhook "http://127.0.0.1:${PF_APPSET_PORT}/api/webhook" correct \
    "${report}/webhook-L6-no-row.json" 'refs/heads/main' "${before_sha}" "${C6B_SHA}" \
    'platforms/canary/services.yaml'
  sit_assert_http_success "${report}/webhook-L6-no-row.json"
  sit_assert_child_specs_stable_for 90 "${report}/child-specs-S6-two-row.json" \
    "${report}/apps-L6-no-row-changed.json"
  capture_child_specs 'L6-no-row-end'
  sit_leg_pass 'two row files changed exactly their four-app union; a roster-only path changed zero specs for 90s'

  sit_leg_begin 'L7-polling-fallback' \
    'git-C7.txt' 'polling-L7.json' 'apps-S7.json' 'child-specs-S7.json' 'changed-L7.json'
  configure_clocks '30s'
  capture_child_specs 'S6-poll-baseline'
  before_sha="${C6B_SHA}"
  yq -i '.pin.tag = "0.1.4-sit-l7"' \
    "${FLEET_SOURCE}/platforms/canary/landscapes/raichu/dummy.yaml"
  local poll_started poll_elapsed
  poll_started="$(sit_epoch)"
  fleet_commit 'C7 raichu polling fallback' "${report}/git-C7.txt" \
    'platforms/canary/landscapes/raichu/dummy.yaml'
  C7_SHA="${FLEET_LAST_COMMIT}"
  sit_wait_for 180 '30s ApplicationSet polling fallback to update raichu' \
    check_child_revision raichu '0.1.4-sit-l7'
  poll_elapsed=$(($(sit_epoch) - poll_started))
  jq -n --arg before "${before_sha}" --arg after "${C7_SHA}" --argjson elapsed "${poll_elapsed}" \
    '{webhookSent:false,before:$before,after:$after,requeue:"30s",elapsed_s:$elapsed}' \
    >"${report}/polling-L7.json"
  capture_child_specs 'S7'
  assert_changed_landscapes "${report}/child-specs-S6-poll-baseline.json" \
    "${report}/child-specs-S7.json" L7 raichu
  sit_leg_pass "polling fallback converged without a webhook in ${poll_elapsed}s"

  assert_clean_unchanged_source "${SIT_SOURCE_HEAD}"
  sit_assert_complete_pass_legs
  sit_report_finish pass
  echo "fleet SIT passed; report: ${SIT_REPORT_FILE}"
}

if [ "${mode}" = 'prepare' ]; then
  prepare_only
else
  run_full
fi
