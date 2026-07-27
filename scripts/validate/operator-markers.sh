#!/usr/bin/env bash
set -euo pipefail

# controller-gen emits a valid-but-weaker CRD when a required marker is absent — docs/domain/operator-conventions.md.

fleet_types_dir="api/fleet/v1alpha1"
problems_types_dir="api/problems/v1alpha1"
controllers_dir="adapters/operator/controllers"
crd_dir="infra/root_chart/templates/crds"
# The census is partitioned so the inherited and Problem halves each fail closed
# on their own: a Problem rule can never be absorbed by an inherited slot.
expected_inherited_cel_count=14
expected_problem_cel_count=5
expected_total_cel_count=19

[ ! -d "${fleet_types_dir}" ] && echo "❌ operator marker lint: missing API types directory ${fleet_types_dir}" >&2 && exit 1
[ ! -d "${problems_types_dir}" ] && echo "❌ operator marker lint: missing API types directory ${problems_types_dir}" >&2 && exit 1
[ ! -d "${controllers_dir}" ] && echo "❌ operator marker lint: missing controllers directory ${controllers_dir}" >&2 && exit 1
[ ! -d "${crd_dir}" ] && echo "❌ operator marker lint: missing CRD directory ${crd_dir}" >&2 && exit 1

# Facts: type|<Kind>|<marker> · printcolumn|<Kind>|<column> · field|<Type>.<Field>|<marker> · rbac|<controller>|<marker> · cel|<Type>.<Field>|<rule>
required="$(
  cat <<'EOF'
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
type|Problem|kubebuilder:object:root=true
type|Problem|kubebuilder:subresource:status
type|Problem|kubebuilder:resource:scope=Namespaced,shortName=prb
printcolumn|Problem|Service
printcolumn|Problem|Landscape
printcolumn|Problem|Version
printcolumn|Problem|Published
printcolumn|Problem|Age
field|ProblemSpec.Platform|kubebuilder:validation:Required
field|ProblemSpec.Platform|kubebuilder:validation:MinLength=1
field|ProblemSpec.Platform|kubebuilder:validation:MaxLength=63
field|ProblemSpec.Platform|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ProblemSpec.Platform|kubebuilder:validation:XValidation:rule="self == oldSelf",message="platform is immutable"
field|ProblemSpec.Service|kubebuilder:validation:Required
field|ProblemSpec.Service|kubebuilder:validation:MinLength=1
field|ProblemSpec.Service|kubebuilder:validation:MaxLength=63
field|ProblemSpec.Service|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ProblemSpec.Service|kubebuilder:validation:XValidation:rule="self == oldSelf",message="service is immutable"
field|ProblemSpec.Landscape|kubebuilder:validation:Required
field|ProblemSpec.Landscape|kubebuilder:validation:MinLength=1
field|ProblemSpec.Landscape|kubebuilder:validation:MaxLength=63
field|ProblemSpec.Landscape|kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
field|ProblemSpec.Landscape|kubebuilder:validation:XValidation:rule="self == oldSelf",message="landscape is immutable"
field|ProblemSpec.Version|kubebuilder:validation:Required
field|ProblemSpec.Version|kubebuilder:validation:MaxLength=16
field|ProblemSpec.Version|kubebuilder:validation:Pattern=`^v\d+$`
field|ProblemSpec.Version|kubebuilder:validation:XValidation:rule="self == oldSelf",message="version is immutable — a version bump is a new CR"
field|ProblemSpec.Problems|optional
field|ProblemSpec.Problems|listType=map
field|ProblemSpec.Problems|listMapKey=id
field|ProblemSpec.Problems|kubebuilder:validation:MaxItems=1024
field|ProblemEntry.ID|kubebuilder:validation:Required
field|ProblemEntry.ID|kubebuilder:validation:MinLength=1
field|ProblemEntry.ID|kubebuilder:validation:MaxLength=63
field|ProblemEntry.ID|kubebuilder:validation:Pattern=`^[a-z][a-z0-9_]*$`
field|ProblemEntry.Type|kubebuilder:validation:Required
field|ProblemEntry.Type|kubebuilder:validation:MaxLength=2048
field|ProblemEntry.Type|kubebuilder:validation:Pattern=`^https://\S+$`
field|ProblemEntry.Title|kubebuilder:validation:Required
field|ProblemEntry.Title|kubebuilder:validation:MinLength=1
field|ProblemEntry.Title|kubebuilder:validation:MaxLength=253
field|ProblemEntry.Status|kubebuilder:validation:Required
field|ProblemEntry.Status|kubebuilder:validation:Minimum=100
field|ProblemEntry.Status|kubebuilder:validation:Maximum=599
field|ProblemEntry.Recoverable|kubebuilder:validation:Required
field|ProblemEntry.Schema|kubebuilder:validation:Required
field|ProblemEntry.Schema|kubebuilder:pruning:PreserveUnknownFields
field|ProblemEntry.Schema|kubebuilder:validation:Type=object
field|ProblemEntry.Endpoints|optional
field|ProblemEntry.Endpoints|listType=atomic
field|ProblemEntry.Endpoints|kubebuilder:validation:MaxItems=64
field|ProblemEndpoint.Method|kubebuilder:validation:Required
field|ProblemEndpoint.Method|kubebuilder:validation:MaxLength=16
field|ProblemEndpoint.Method|kubebuilder:validation:Pattern=`^[A-Z]+$`
field|ProblemEndpoint.Path|kubebuilder:validation:Required
field|ProblemEndpoint.Path|kubebuilder:validation:MinLength=1
field|ProblemEndpoint.Path|kubebuilder:validation:MaxLength=512
field|ProblemEndpoint.Path|kubebuilder:validation:Pattern=`^/`
field|ProblemStatus.Conditions|optional
field|ProblemStatus.Conditions|listType=map
field|ProblemStatus.Conditions|listMapKey=type
field|ProblemStatus.ObservedGeneration|optional
cel|Problem|self.metadata.name == self.spec.service + '-' + self.spec.landscape + '-' + self.spec.version
cel|ProblemSpec.Platform|self == oldSelf
cel|ProblemSpec.Service|self == oldSelf
cel|ProblemSpec.Landscape|self == oldSelf
cel|ProblemSpec.Version|self == oldSelf
EOF
)"

echo "🔎 extracting kubebuilder markers from ${fleet_types_dir}, ${problems_types_dir} and ${controllers_dir}"

# Each marker block counts only at the declaration it precedes, never file-wide.
facts=""
open='struct {'
for file in "${fleet_types_dir}"/*_types.go "${problems_types_dir}"/*_types.go; do
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

# Three deduplicated censuses over one fact stream. The inherited view is every
# CEL fact that is NOT a Problem fact, the Problem view is exactly the Problem
# prefix, and the total is every CEL fact — so a rule that moves between
# partitions, or appears in one side only, cannot net out to a passing count.
count_inherited_cel_facts() {
  sed -n '/^cel|Problem/d; /^cel|/p' |
    sort -u |
    wc -l |
    tr -d '[:space:]'
}

count_problem_cel_facts() {
  sed -n '/^cel|Problem/p' |
    sort -u |
    wc -l |
    tr -d '[:space:]'
}

count_total_cel_facts() {
  sed -n '/^cel|/p' |
    sort -u |
    wc -l |
    tr -d '[:space:]'
}

required_inherited_cel_count="$(count_inherited_cel_facts <<<"${required}")"
required_problem_cel_count="$(count_problem_cel_facts <<<"${required}")"
required_total_cel_count="$(count_total_cel_facts <<<"${required}")"
actual_inherited_cel_count="$(count_inherited_cel_facts <<<"${facts}")"
actual_problem_cel_count="$(count_problem_cel_facts <<<"${facts}")"
actual_total_cel_count="$(count_total_cel_facts <<<"${facts}")"

if [ "${required_inherited_cel_count}" -ne "${expected_inherited_cel_count}" ]; then
  echo "❌ operator marker lint: declared inherited CEL census is ${required_inherited_cel_count}, expected ${expected_inherited_cel_count}" >&2
  exit 1
fi
if [ "${required_problem_cel_count}" -ne "${expected_problem_cel_count}" ]; then
  echo "❌ operator marker lint: declared problem CEL census is ${required_problem_cel_count}, expected ${expected_problem_cel_count}" >&2
  exit 1
fi
if [ "${required_total_cel_count}" -ne "${expected_total_cel_count}" ]; then
  echo "❌ operator marker lint: declared total CEL census is ${required_total_cel_count}, expected ${expected_total_cel_count}" >&2
  exit 1
fi
if [ "${actual_inherited_cel_count}" -ne "${expected_inherited_cel_count}" ]; then
  echo "❌ operator marker lint: source inherited CEL census is ${actual_inherited_cel_count}, expected ${expected_inherited_cel_count}" >&2
  exit 1
fi
if [ "${actual_problem_cel_count}" -ne "${expected_problem_cel_count}" ]; then
  echo "❌ operator marker lint: source problem CEL census is ${actual_problem_cel_count}, expected ${expected_problem_cel_count}" >&2
  exit 1
fi
if [ "${actual_total_cel_count}" -ne "${expected_total_cel_count}" ]; then
  echo "❌ operator marker lint: source total CEL census is ${actual_total_cel_count}, expected ${expected_total_cel_count}" >&2
  exit 1
fi
echo "🧮 CEL census: policy inherited=${required_inherited_cel_count} problem=${required_problem_cel_count} total=${required_total_cel_count}"
echo "🧮 CEL census: source inherited=${actual_inherited_cel_count} problem=${actual_problem_cel_count} total=${actual_total_cel_count}"

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

policy_rbac_count="$(sed -n '/^rbac|/p' <<<"${required}" | wc -l | tr -d '[:space:]')"
source_rbac_count="$(sed -n '/^rbac|/p' <<<"${facts}" | wc -l | tr -d '[:space:]')"
generated_grant_count="$(yq -r '.rules | length' infra/root_chart/templates/rbac/role.yaml)"
if [ "${source_rbac_count}" -ne "${policy_rbac_count}" ]; then
  echo "❌ operator marker lint: source RBAC facts ${source_rbac_count} != policy RBAC facts ${policy_rbac_count}" >&2
  exit 1
fi
if [ "${generated_grant_count}" -ne "${policy_rbac_count}" ]; then
  echo "❌ operator marker lint: generated grants ${generated_grant_count} != policy RBAC facts ${policy_rbac_count}" >&2
  exit 1
fi
echo "🧮 policy rbac facts: ${policy_rbac_count} == generated grants: ${generated_grant_count}"

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
