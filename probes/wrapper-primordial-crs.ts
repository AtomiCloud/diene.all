import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

// The shared validation script owns the shape checks that hold for a single render.
// Identity is a per-landscape claim, so it needs two renders of the same chart and a
// pair of refusals, which this probe drives itself. The heredoc keeps the assertions
// verbatim, and the script file lives outside the repository so no probe fixture is
// left behind in the sandbox.
const identityAssertions = `
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "❌ $1" >&2
  exit 1
}

# Render one primordial set for a concrete target landscape under one consumer platform.
render() {
  helm template helm-wrapper chart --namespace "$2" --values chart/values.example.yaml --set primordial.enabled=true --set serviceTree.platform="$2" --set serviceTree.landscape="$1" --set primordial.targetLandscape="$1"
}

# Every document of one rendered set that carries the requested kind, as a JSON array.
documents() {
  yq eval-all -o=json '.' "$1" | jq -s --arg kind "$2" 'map(select(.kind == $kind))'
}

# A target landscape the identity helper must refuse outright.
refuse() {
  if helm template helm-wrapper chart --namespace sample --values chart/values.example.yaml --set primordial.enabled=true --set primordial.targetLandscape="$1" >/dev/null 2>&1; then
    fail "$2"
  fi
}

render serving sample >"$work/serving.yaml"
render staging sample >"$work/staging.yaml"
kubeconform -strict -summary -schema-location default -schema-location 'schemas/{{ .ResourceKind }}.json' "$work/serving.yaml" "$work/staging.yaml"

for landscape in serving staging; do
  rendered="$work/$landscape.yaml"
  if [ "$landscape" = serving ]; then sibling=staging; else sibling=serving; fi

  # Exactly one landscape-targeted identity CR per (app x landscape), whose identityRef
  # is exactly the {platform, landscape} pair and carries no virtual landscape.
  documents "$rendered" LogtoApp |
    jq -e --arg landscape "$landscape" 'length == 1 and (.[0].spec.identityRef == { platform: "sample", landscape: $landscape })' >/dev/null ||
    fail "LogtoApp identityRef is not the exact {platform, landscape} pair for $landscape"

  # The CR itself is landscape-distinct: the landscape fuses into the dashless token, so
  # the name keeps exactly one dash and a second landscape cannot reuse this CR.
  documents "$rendered" LogtoApp |
    jq -e --arg name "wrapper-identity$landscape" '.[0].metadata.name == $name and (.[0].metadata.name | test("^[a-z0-9]+-[a-z0-9]+$"))' >/dev/null ||
    fail "the $landscape identity CR is not named by the landscape-fused one-dash convention"

  # That landscape's issuer and application resolve through the one fixed fleet endpoint.
  endpoint="api.lithium.aldehyde.$landscape.cluster.atomi.cloud"
  documents "$rendered" LogtoApp |
    jq -e --arg endpoint "$endpoint" '.[0].metadata.annotations["atomi.cloud/identity-endpoint"] == $endpoint' >/dev/null ||
    fail "the identity endpoint for $landscape is not $endpoint"

  # Generated credentials have exactly one destination: the sibling landscape is named
  # nowhere in the identity CR, so no sibling fan-out can be expressed.
  documents "$rendered" LogtoApp |
    jq -e --arg sibling "$sibling" 'tostring | contains($sibling) | not' >/dev/null ||
    fail "the $landscape identity CR names sibling landscape $sibling"
done

serving_landscape="$(documents "$work/serving.yaml" LogtoApp | jq -r '.[0].spec.identityRef.landscape')"
staging_landscape="$(documents "$work/staging.yaml" LogtoApp | jq -r '.[0].spec.identityRef.landscape')"
[ "$serving_landscape" != "$staging_landscape" ] || fail "two target landscapes shared one identity"

serving_name="$(documents "$work/serving.yaml" LogtoApp | jq -r '.[0].metadata.name')"
staging_name="$(documents "$work/staging.yaml" LogtoApp | jq -r '.[0].metadata.name')"
[ "$serving_name" != "$staging_name" ] || fail "two target landscapes reused one identity CR name"

# The consumer platform is recorded from the release namespace and never reaches the
# issuer segments, which stay fixed to aldehyde's lithium api.
render serving nitroso >"$work/other.yaml"
other_platform="$(documents "$work/other.yaml" LogtoApp | jq -r '.[0].spec.identityRef.platform')"
other_endpoint="$(documents "$work/other.yaml" LogtoApp | jq -r '.[0].metadata.annotations["atomi.cloud/identity-endpoint"]')"
[ "$other_platform" = nitroso ] || fail "identityRef.platform is not sourced from the release namespace"
[ "$other_endpoint" = "api.lithium.aldehyde.serving.cluster.atomi.cloud" ] || fail "the consumer platform leaked into the identity endpoint"

refuse example-vlandscape "a virtual landscape was accepted as an issuer segment"
refuse sample "the consumer platform was accepted as an issuer segment"
refuse serving.cluster "a multi-segment landscape was accepted as an issuer segment"

# Problem carries the LPSM module and tracks the service tree rather than a free value.
documents "$work/serving.yaml" Problem |
  jq -e 'length == 1 and (.[0].spec.module == "api")' >/dev/null ||
  fail "Problem.spec.module is not the service-tree module"
helm template helm-wrapper chart --namespace sample --values chart/values.example.yaml --set primordial.enabled=true --set serviceTree.module=worker >"$work/module.yaml"
documents "$work/module.yaml" Problem |
  jq -e '.[0].spec.module == "worker"' >/dev/null ||
  fail "Problem.spec.module does not follow the service-tree module"
`;

const identityCommand = [
  'assertions="$(mktemp)"',
  'cat >"$assertions" <<\'PRIMORDIAL_ASSERTIONS\'',
  identityAssertions,
  'PRIMORDIAL_ASSERTIONS',
  'nix develop .#ci -c bash "$assertions"',
  'status=$?',
  'rm -f "$assertions"',
  'exit $status',
].join('\n');

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-primordial-crs-green',
    description:
      'All five primordial helpers validate against the frozen local T3 shape schemas, two target landscapes render distinct exact identities, and Problem carries the service-tree module.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh primordial',
        'wrapper-primordial-crs',
      );
      await expectGreen(repo, identityCommand, 'wrapper-primordial-crs identity');
    },
  },
  mutation: {
    name: 'mutation-wrapper-primordial-crs-caught',
    description: 'A removed sharing field is rejected by the PlatformDependency schema.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/templates/primordial-resources.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: '  landscape: {{ .Values.primordial.targetLandscape }}\n  placement:',
          replace: '  landscape: {{ .Values.primordial.targetLandscape }}\n  share: true\n  placement:',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh primordial',
          'wrapper-primordial-crs',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
