#!/usr/bin/env bash
set -euo pipefail

# controller-gen emits a valid-but-weaker CRD when a required marker is absent — docs/domain/operator-conventions.md.

types_dir="api/v1alpha1"
fleet_types_dir="api/fleet/v1alpha1"
controllers_dir="adapters/operator/controllers"
crd_dir="infra/root_chart/templates/crds"
expected_workload_cel_count=13

[ ! -d "${types_dir}" ] && echo "❌ operator marker lint: missing API types directory ${types_dir}" >&2 && exit 1
[ ! -d "${fleet_types_dir}" ] && echo "❌ operator marker lint: missing API types directory ${fleet_types_dir}" >&2 && exit 1
[ ! -d "${controllers_dir}" ] && echo "❌ operator marker lint: missing controllers directory ${controllers_dir}" >&2 && exit 1
[ ! -d "${crd_dir}" ] && echo "❌ operator marker lint: missing CRD directory ${crd_dir}" >&2 && exit 1

# Facts: type|<Kind>|<marker> · printcolumn|<Kind>|<column> · field|<Type>.<Field>|<marker> · rbac|<controller>|<marker> · cel|<Type>.<Field>|<rule>
required="$(
  cat <<'EOF'
type|Note|kubebuilder:object:root=true
type|Note|kubebuilder:subresource:status
type|Note|kubebuilder:resource:scope=Namespaced,shortName=nt
printcolumn|Note|Category
printcolumn|Note|Copies
printcolumn|Note|Ready
printcolumn|Note|Age
field|NoteSpec.Title|kubebuilder:validation:Required
field|NoteSpec.Title|kubebuilder:validation:MinLength=1
field|NoteSpec.Title|kubebuilder:validation:MaxLength=253
field|NoteSpec.Body|kubebuilder:validation:Required
field|NoteSpec.Body|kubebuilder:validation:MinLength=1
field|NoteSpec.Category|kubebuilder:validation:Required
field|NoteSpec.Category|kubebuilder:validation:Enum=personal;work;archive
field|NoteSpec.Replicas|kubebuilder:validation:Minimum=0
field|NoteSpec.Replicas|kubebuilder:validation:Maximum=50
field|NoteSpec.Replicas|kubebuilder:default=1
field|NoteStatus.Conditions|listType=map
field|NoteStatus.Conditions|listMapKey=type
type|Journal|kubebuilder:object:root=true
type|Journal|kubebuilder:subresource:status
type|Journal|kubebuilder:resource:scope=Namespaced,shortName=jn
printcolumn|Journal|Ready
printcolumn|Journal|Age
field|JournalSpec.Message|kubebuilder:validation:Required
field|JournalSpec.Message|kubebuilder:validation:MinLength=1
field|JournalSpec.Message|kubebuilder:validation:MaxLength=1024
field|JournalStatus.Conditions|listType=map
field|JournalStatus.Conditions|listMapKey=type
rbac|note|groups=sample.diene.atomi.cloud,resources=notes,verbs=get;list;watch;update
rbac|note|groups=sample.diene.atomi.cloud,resources=notes/status,verbs=get;update;patch
rbac|note|groups=sample.diene.atomi.cloud,resources=notes/finalizers,verbs=update
rbac|note|groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
rbac|note|groups="",resources=events,verbs=create;patch
rbac|note|groups=authentication.k8s.io,resources=tokenreviews,verbs=create
rbac|note|groups=authorization.k8s.io,resources=subjectaccessreviews,verbs=create
rbac|note|groups=coordination.k8s.io,resources=leases,verbs=get;create;update
rbac|journal|groups=sample.diene.atomi.cloud,resources=journals,verbs=get;list;watch
rbac|journal|groups=sample.diene.atomi.cloud,resources=journals/status,verbs=get;update;patch
type|Landscape|kubebuilder:object:root=true
type|Landscape|kubebuilder:subresource:status
type|Landscape|kubebuilder:resource:scope=Cluster,shortName=lsc
printcolumn|Landscape|Region
printcolumn|Landscape|Tier
printcolumn|Landscape|Purpose
printcolumn|Landscape|Age
field|LandscapeSpec.Region|kubebuilder:validation:Required
field|LandscapeSpec.Region|kubebuilder:validation:MinLength=1
field|LandscapeSpec.Region|kubebuilder:validation:MaxLength=63
field|LandscapeSpec.Region|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|LandscapeSpec.Region|kubebuilder:validation:XValidation:rule="self == oldSelf",message="region is immutable"
field|LandscapeSpec.Tier|kubebuilder:validation:MinLength=1
field|LandscapeSpec.Tier|kubebuilder:validation:MaxLength=63
field|LandscapeSpec.Purpose|kubebuilder:validation:Enum=infrastructure-only
field|LandscapeStatus.Conditions|listType=map
field|LandscapeStatus.Conditions|listMapKey=type
cel|LandscapeSpec.Region|self == oldSelf
type|ClusterRegistration|kubebuilder:object:root=true
type|ClusterRegistration|kubebuilder:subresource:status
type|ClusterRegistration|kubebuilder:resource:scope=Cluster,shortName=creg
printcolumn|ClusterRegistration|Landscape
printcolumn|ClusterRegistration|Provider
printcolumn|ClusterRegistration|Traffic
printcolumn|ClusterRegistration|Phase
printcolumn|ClusterRegistration|Accepting
printcolumn|ClusterRegistration|Age
field|ClusterRegistrationSpec.Landscape|kubebuilder:validation:Required
field|ClusterRegistrationSpec.Landscape|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ClusterRegistrationSpec.Mark|kubebuilder:validation:Required
field|ClusterRegistrationSpec.Mark|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ClusterRegistrationSpec.Provider|kubebuilder:validation:Required
field|ClusterRegistrationSpec.Provider|kubebuilder:validation:Enum=doks;eks;oke
field|ClusterRegistrationSpec.OriginMode|kubebuilder:validation:Required
field|ClusterRegistrationSpec.OriginMode|kubebuilder:validation:Enum=loadbalancer
field|ClusterRegistrationSpec.OriginMode|kubebuilder:default=loadbalancer
field|ClusterRegistrationSpec.Traffic|kubebuilder:validation:Required
field|ClusterRegistrationSpec.HostRole|kubebuilder:validation:Enum=anonymous-vcluster-host
field|ClusterRegistrationStatus.Phase|kubebuilder:validation:Enum=provisioning;ready;decommissioned
field|ClusterRegistrationStatus.LBIPs|listType=map
field|ClusterRegistrationStatus.LBIPs|listMapKey=ip
field|ClusterRegistrationStatus.Conditions|listType=map
field|ClusterRegistrationStatus.Conditions|listMapKey=type
field|LoadBalancerIP.IP|kubebuilder:validation:Required
field|LoadBalancerIP.GuaranteeClass|kubebuilder:validation:Required
field|LoadBalancerIP.GuaranteeClass|kubebuilder:validation:Enum=reserved;eip;lb-lifetime
type|VirtualLandscape|kubebuilder:object:root=true
type|VirtualLandscape|kubebuilder:subresource:status
type|VirtualLandscape|kubebuilder:resource:scope=Cluster,shortName=vlsc
printcolumn|VirtualLandscape|Hosts
printcolumn|VirtualLandscape|Age
field|VirtualLandscapeSpec.Hosts|kubebuilder:validation:Required
field|VirtualLandscapeSpec.Hosts|kubebuilder:validation:MinItems=1
field|VirtualLandscapeSpec.Hosts|listType=set
field|VirtualLandscapeSpec.Hosts|kubebuilder:validation:items:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|VirtualLandscapeStatus.Conditions|listType=map
field|VirtualLandscapeStatus.Conditions|listMapKey=type
type|Platform|kubebuilder:object:root=true
type|Platform|kubebuilder:subresource:status
type|Platform|kubebuilder:resource:scope=Namespaced,shortName=plat
printcolumn|Platform|Project
printcolumn|Platform|Ready
printcolumn|Platform|Age
field|PlatformSpec.Infisical|kubebuilder:validation:Required
field|PlatformSpec.SoS|kubebuilder:validation:Required
field|PlatformSpec.Pipeline|kubebuilder:validation:Required
field|PlatformInfisicalSpec.ProjectSlug|kubebuilder:validation:Required
field|PlatformInfisicalSpec.ServiceFolders|kubebuilder:validation:Required
field|PlatformSoSSpec.Register|kubebuilder:validation:Required
field|PlatformPipelineSpec.Stages|kubebuilder:validation:Required
field|PlatformPipelineSpec.Stages|kubebuilder:validation:MinItems=1
field|PlatformStatus.Belt|listType=set
field|PlatformStatus.Conditions|listType=map
field|PlatformStatus.Conditions|listMapKey=type
type|ProviderAccount|kubebuilder:object:root=true
type|ProviderAccount|kubebuilder:subresource:status
type|ProviderAccount|kubebuilder:resource:scope=Namespaced,shortName=pacct
printcolumn|ProviderAccount|Vendor
printcolumn|ProviderAccount|Account
printcolumn|ProviderAccount|Plan
printcolumn|ProviderAccount|Age
field|ProviderAccountSpec.Vendor|kubebuilder:validation:Required
field|ProviderAccountSpec.Vendor|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ProviderAccountSpec.Name|kubebuilder:validation:Required
field|ProviderAccountSpec.Name|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ProviderAccountQuotaSpec.Resource|kubebuilder:validation:Required
field|ProviderAccountQuotaSpec.Limit|kubebuilder:validation:Required
field|ProviderAccountQuotaSpec.Limit|kubebuilder:validation:Minimum=0
field|ProviderAccountStatus.Conditions|listType=map
field|ProviderAccountStatus.Conditions|listMapKey=type
type|PlatformDependency|kubebuilder:object:root=true
type|PlatformDependency|kubebuilder:subresource:status
type|PlatformDependency|kubebuilder:resource:scope=Namespaced,shortName=pdep
printcolumn|PlatformDependency|Platform
printcolumn|PlatformDependency|Landscape
printcolumn|PlatformDependency|Ready
printcolumn|PlatformDependency|Age
field|PlatformDependencySpec.Platform|kubebuilder:validation:Required
field|PlatformDependencySpec.Service|kubebuilder:validation:Optional
field|PlatformDependencySpec.Landscape|kubebuilder:validation:Required
field|PlatformDependencySpec.Placement|kubebuilder:validation:Optional
field|PlatformDependencySpec.Database|kubebuilder:validation:Optional
field|PlatformDependencySpec.KV|kubebuilder:validation:Optional
field|PlatformDependencySpec.Cache|kubebuilder:validation:Optional
field|PlatformDependencySpec.Store|kubebuilder:validation:Optional
field|PlatformDependencySpec.Email|kubebuilder:validation:Optional
field|PlatformDependencySpec.DeletionPolicy|kubebuilder:validation:Optional
field|PlatformDependencySpec.DeletionPolicy|kubebuilder:default={retainSecret: "168h"}
field|DependencyPlacement.PreferredHost|kubebuilder:validation:Required
field|DependencyDeletionPolicy.RetainSecret|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.Type|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.Type|kubebuilder:validation:Enum=neon;neon-fork;cnpg;upstash;upstash-fork;dragonfly;tigris;tigris-fork;r2;s3;minio;ses;cf-email-sending;mailpit
field|PlatformDependencyModuleSpec.Delivery|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.Delivery|kubebuilder:validation:Enum=external;local;replicated
field|PlatformDependencyModuleSpec.Account|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.ProviderAccountRef|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.CredentialMode|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.CredentialMode|kubebuilder:validation:Enum=standard;none
field|PlatformDependencyModuleSpec.Rotation|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.Rotation|kubebuilder:validation:Enum=on;off
field|PlatformDependencyModuleSpec.CPU|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.RAM|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.Storage|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.Version|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.Backup|kubebuilder:validation:Optional
field|PlatformDependencyModuleSpec.Engine|kubebuilder:validation:Required
field|PlatformDependencyModuleSpec.Adopt|kubebuilder:validation:Optional
field|PlatformDependencyStatus.Modules|optional
field|PlatformDependencyStatus.Conditions|listType=map
field|PlatformDependencyStatus.Conditions|listMapKey=type
field|PlatformDependencyModuleStatus.Conditions|listType=map
field|PlatformDependencyModuleStatus.Conditions|listMapKey=type
cel|PlatformDependencyModuleSpec|has(self.engine.neon) == (self.type == 'neon') && has(self.engine.neon__dash__fork) == (self.type == 'neon-fork') && has(self.engine.cnpg) == (self.type == 'cnpg') && has(self.engine.upstash) == (self.type == 'upstash') && has(self.engine.upstash__dash__fork) == (self.type == 'upstash-fork') && has(self.engine.dragonfly) == (self.type == 'dragonfly') && has(self.engine.tigris) == (self.type == 'tigris') && has(self.engine.tigris__dash__fork) == (self.type == 'tigris-fork') && has(self.engine.r2) == (self.type == 'r2') && has(self.engine.s3) == (self.type == 's3') && has(self.engine.minio) == (self.type == 'minio') && has(self.engine.ses) == (self.type == 'ses') && has(self.engine.cf__dash__email__dash__sending) == (self.type == 'cf-email-sending') && has(self.engine.mailpit) == (self.type == 'mailpit')
cel|PlatformDependencyModuleSpec|self.type in ['neon','neon-fork','upstash','upstash-fork','tigris','tigris-fork','r2','s3','ses','cf-email-sending'] ? self.delivery == 'external' : self.type in ['cnpg','minio','mailpit'] ? self.delivery == 'local' : self.type == 'dragonfly' ? self.delivery in ['local','replicated'] : false
cel|PlatformDependencyModuleSpec|(self.delivery == 'external' && has(self.providerAccountRef)) || (self.delivery != 'external' && !has(self.providerAccountRef) && !has(self.account))
cel|PlatformDependencyModuleSpec|!has(self.account) || !has(self.providerAccountRef) || self.account.name == self.providerAccountRef
cel|PlatformDependencySpec.Database|self.all(k, m, m.type in ['neon','neon-fork','cnpg'])
cel|PlatformDependencySpec.KV|self.all(k, m, m.type in ['upstash','upstash-fork','dragonfly'])
cel|PlatformDependencySpec.Cache|self.all(k, m, m.type == 'dragonfly')
cel|PlatformDependencySpec.Store|self.all(k, m, m.type in ['tigris','tigris-fork','r2','s3','minio'])
cel|PlatformDependencySpec.Email|self.all(k, m, m.type in ['ses','cf-email-sending','mailpit'])
type|VirtualLandscapeService|kubebuilder:object:root=true
type|VirtualLandscapeService|kubebuilder:subresource:status
type|VirtualLandscapeService|kubebuilder:resource:scope=Namespaced,shortName=vls
printcolumn|VirtualLandscapeService|VLandscape
printcolumn|VirtualLandscapeService|Landscape
printcolumn|VirtualLandscapeService|Serve
printcolumn|VirtualLandscapeService|Ready
printcolumn|VirtualLandscapeService|Age
field|VirtualLandscapeServiceSpec.Platform|kubebuilder:validation:Required
field|VirtualLandscapeServiceSpec.VLandscape|kubebuilder:validation:Required
field|VirtualLandscapeServiceSpec.Service|kubebuilder:validation:Required
field|VirtualLandscapeServiceSpec.Module|kubebuilder:validation:Required
field|VirtualLandscapeServiceSpec.Landscape|kubebuilder:validation:Required
field|VirtualLandscapeServiceSpec.Serve|kubebuilder:validation:Required
field|VirtualLandscapeServiceStatus.Modules|optional
field|VirtualLandscapeServiceStatus.Conditions|listType=map
field|VirtualLandscapeServiceStatus.Conditions|listMapKey=type
field|VirtualLandscapeServiceModuleStatus.Conditions|listType=map
field|VirtualLandscapeServiceModuleStatus.Conditions|listMapKey=type
type|WebhookEngine|kubebuilder:object:root=true
type|WebhookEngine|kubebuilder:subresource:status
type|WebhookEngine|kubebuilder:resource:scope=Namespaced,shortName=wheng
printcolumn|WebhookEngine|Home
printcolumn|WebhookEngine|Ready
printcolumn|WebhookEngine|Age
field|WebhookEngineSpec.Home|kubebuilder:validation:Required
field|WebhookEngineSpec.Retention|kubebuilder:validation:Required
field|WebhookEngineSpec.RetryWindow|kubebuilder:validation:Required
field|WebhookEngineSpec.Backoff|kubebuilder:validation:Required
field|WebhookEngineSpec.CircuitBreaker|kubebuilder:validation:Required
field|WebhookEngineSpec.DedupWindow|kubebuilder:validation:Required
field|WebhookEngineSpec.Quotas|kubebuilder:validation:Required
field|WebhookEngineSpec.CustomDomains|kubebuilder:validation:Optional
field|WebhookEngineHome.VLandscape|kubebuilder:validation:XValidation:rule="self == oldSelf",message="home.vlandscape is immutable"
field|WebhookEngineStatus.Conditions|listType=map
field|WebhookEngineStatus.Conditions|listMapKey=type
field|WebhookLandscapeStatus.Conditions|listType=map
field|WebhookLandscapeStatus.Conditions|listMapKey=type
field|WebhookProviderStatus.Conditions|listType=map
field|WebhookProviderStatus.Conditions|listMapKey=type
cel|WebhookEngineHome.VLandscape|self == oldSelf
type|WebhookRoute|kubebuilder:object:root=true
type|WebhookRoute|kubebuilder:subresource:status
type|WebhookRoute|kubebuilder:resource:scope=Namespaced,shortName=whr
printcolumn|WebhookRoute|Engine
printcolumn|WebhookRoute|Provider
printcolumn|WebhookRoute|Path
printcolumn|WebhookRoute|Ready
printcolumn|WebhookRoute|Age
field|WebhookRouteSpec.Engine|kubebuilder:validation:Required
field|WebhookRouteSpec.Path|kubebuilder:validation:Required
field|WebhookRouteSpec.Provider|kubebuilder:validation:Required
field|WebhookRouteSpec.Scheme|kubebuilder:validation:Optional
field|WebhookRouteSpec.Target|kubebuilder:validation:Required
field|WebhookRouteStatus.Conditions|listType=map
field|WebhookRouteStatus.Conditions|listMapKey=type
type|CloudflareDeploy|kubebuilder:object:root=true
type|CloudflareDeploy|kubebuilder:subresource:status
type|CloudflareDeploy|kubebuilder:resource:scope=Namespaced,shortName=cfd
printcolumn|CloudflareDeploy|Script
printcolumn|CloudflareDeploy|Live
printcolumn|CloudflareDeploy|Complete
printcolumn|CloudflareDeploy|Age
field|CloudflareDeploySpec.ScriptName|kubebuilder:validation:Required
field|CloudflareDeploySpec.DesiredVersion|kubebuilder:validation:Optional
field|CloudflareDeploySpec.DesiredVersionFrom|kubebuilder:validation:Optional
field|CloudflareDeploySpec.Rollout|kubebuilder:validation:Optional
field|CloudflareDeploySpec.Pin|kubebuilder:validation:Required
field|CloudflareRollout.Steps|kubebuilder:validation:XValidation:rule="self.exists(step, step.percent == 100)",message="rollout steps must contain a 100 percent step"
field|CloudflareDeployStatus.Conditions|listType=map
field|CloudflareDeployStatus.Conditions|listMapKey=type
cel|CloudflareDeploySpec|has(self.desiredVersion) != has(self.desiredVersionFrom)
cel|CloudflareRollout.Steps|self.exists(step, step.percent == 100)
type|Decommission|kubebuilder:object:root=true
type|Decommission|kubebuilder:subresource:status
type|Decommission|kubebuilder:resource:scope=Namespaced,shortName=decom
printcolumn|Decommission|Kind
printcolumn|Decommission|Target
printcolumn|Decommission|Deleted
printcolumn|Decommission|Age
field|DecommissionSpec.TargetRef|kubebuilder:validation:Required
field|DecommissionSpec.Confirm|kubebuilder:validation:Required
field|DecommissionStatus.Conditions|listType=map
field|DecommissionStatus.Conditions|listMapKey=type
cel|DecommissionSpec|self.confirm == self.targetRef.name
EOF
)"

echo "🔎 extracting kubebuilder markers from ${types_dir}, ${fleet_types_dir} and ${controllers_dir}"

# Each marker block counts only at the declaration it precedes, never file-wide.
facts=""
open='struct {'
for file in "${types_dir}"/*_types.go "${fleet_types_dir}"/*_types.go; do
  [ ! -f "${file}" ] && continue
  scope=""
  inside=0
  pending=""
  while IFS= read -r raw; do
    line="${raw#"${raw%%[![:space:]]*}"}"
    [ -z "${line}" ] && pending="" && continue
    [ "${raw}" = "}" ] && scope="" && inside=0 && pending="" && continue
    [ "${line}" != "${line#// +}" ] && pending="${pending}${line#// +}"$'\n' && continue
    [ "${line}" != "${line#//}" ] && continue
    decl=""
    [ "${line}" != "${line#type }" ] && [ "${line}" != "${line%"${open}"}" ] && scope="${line#type }" && scope="${scope%% *}" && inside=1 && decl="type|${scope}"
    [ "${inside}" = 1 ] && [ -z "${decl}" ] && [ "${line}" != "${line#[A-Z]}" ] && field="${line%% *}" && [ "${field}" = "${field%.*}" ] && decl="field|${scope}.${field}" && facts="${facts}fieldof|${scope}|${field}"$'\n'
    [ -z "${decl}" ] && pending="" && continue
    while IFS= read -r marker; do
      [ -z "${marker}" ] && continue
      facts="${facts}${decl}|${marker}"$'\n'
    done <<<"${pending}"
    pending=""
  done <"${file}"
done

for file in "${controllers_dir}"/*_controller.go; do
  [ ! -f "${file}" ] && continue
  controller="${file##*/}"
  controller="${controller%_controller.go}"
  while IFS= read -r marker; do
    [ -z "${marker}" ] && continue
    facts="${facts}rbac|${controller}|${marker#*+kubebuilder:rbac:}"$'\n'
  done <<<"$(grep -F '+kubebuilder:rbac:' "${file}" || true)"
done

facts="${facts}$(grep -F 'kubebuilder:printcolumn:name=' <<<"${facts}" | sed -E 's/^type\|([^|]+)\|kubebuilder:printcolumn:name="([^"]+)".*/printcolumn|\1|\2/' || true)"$'\n'

# A CEL rule is schema-level behaviour, so the policy pins its exact expression rather than its presence.
facts="${facts}$(sed -nE 's/^(type|field)\|([^|]+)\|kubebuilder:validation:XValidation:rule="([^"]*)".*/cel|\2|\3/p' <<<"${facts}" || true)"$'\n'

count_workload_cel_facts() {
  sed -n '/^cel|LandscapeSpec\.Region|/d; /^cel|/p' |
    sort -u |
    wc -l |
    tr -d '[:space:]'
}

required_workload_cel_count="$(count_workload_cel_facts <<<"${required}")"
actual_workload_cel_count="$(count_workload_cel_facts <<<"${facts}")"

if [ "${required_workload_cel_count}" -ne "${expected_workload_cel_count}" ]; then
  echo "❌ operator marker lint: declared workload CEL census is ${required_workload_cel_count}, expected ${expected_workload_cel_count}" >&2
  exit 1
fi
if [ "${actual_workload_cel_count}" -ne "${expected_workload_cel_count}" ]; then
  echo "❌ operator marker lint: source workload CEL census is ${actual_workload_cel_count}, expected ${expected_workload_cel_count}" >&2
  exit 1
fi
echo "🧮 workload CEL census: ${actual_workload_cel_count}"

echo "🧪 asserting the required marker families"

while IFS= read -r want; do
  [ -z "${want}" ] && continue
  ! grep -qxF "${want}" <<<"${facts}" && echo "❌ operator marker lint: required marker missing → ${want}" >&2 && exit 1
done <<<"${required}"

# The declared grants are the whole grant set, so an unlisted one is a silent privilege addition.
while IFS= read -r got; do
  [ -z "${got}" ] && continue
  ! grep -qxF "${got}" <<<"${required}" && echo "❌ operator marker lint: RBAC marker outside the declared grant set → ${got}" >&2 && exit 1
done <<<"$(grep '^rbac|' <<<"${facts}" || true)"

# The declared rules are the whole CEL set, so an unlisted or reworded rule is a silent schema change.
while IFS= read -r got; do
  [ -z "${got}" ] && continue
  ! grep -qxF "${got}" <<<"${required}" && echo "❌ operator marker lint: CEL rule outside the declared rule set → ${got}" >&2 && exit 1
done <<<"$(grep '^cel|' <<<"${facts}" || true)"

# A newly served kind must arrive with its own requirement instead of inheriting silence.
while IFS= read -r kind; do
  [ -z "${kind}" ] && continue
  ! grep -qxF "type|${kind}|kubebuilder:subresource:status" <<<"${required}" && echo "❌ operator marker lint: served kind ${kind} has no status-subresource requirement in this gate" >&2 && exit 1
  ! grep -q "^printcolumn|${kind}|" <<<"${required}" && echo "❌ operator marker lint: served kind ${kind} has no print-column requirement in this gate" >&2 && exit 1
done <<<"$(yq -r '.spec.names.kind' "${crd_dir}"/*.yaml | grep -v '^---$' || true)"

while IFS= read -r entry; do
  [ -z "${entry}" ] && continue
  target="${entry#fieldof|}"
  ! grep -q "^field|${target/|/.}|kubebuilder:validation:" <<<"${facts}" && echo "❌ operator marker lint: spec field ${target/|/.} carries no +kubebuilder:validation marker" >&2 && exit 1
done <<<"$(grep -E '^fieldof\|[A-Za-z0-9_]+Spec\|' <<<"${facts}" || true)"

echo "✅ operator marker lint passed"
