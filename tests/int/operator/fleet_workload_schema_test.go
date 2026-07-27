package operator_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	"sigs.k8s.io/controller-runtime/pkg/client"

	fleetv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/fleet/v1alpha1"
)

const fleetWorkloadFixtureCount = 6

func loadFleetWorkloadFixture(t *testing.T, name string) *unstructured.Unstructured {
	t.Helper()
	//nolint:gosec // The fixture name is a test-local literal under the repository's fixture directory.
	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "operator", "fleet", "workload", name))
	require.NoError(t, err)
	converted, err := utilyaml.ToJSON(raw)
	require.NoError(t, err)
	obj := &unstructured.Unstructured{}
	require.NoError(t, obj.UnmarshalJSON(converted))
	return obj
}

func createFleetWorkloadFixture(t *testing.T, c client.Client, obj *unstructured.Unstructured) {
	t.Helper()
	require.NoError(t, c.Create(context.Background(), obj))
	t.Cleanup(func() { _ = c.Delete(context.Background(), obj) })
}

func requireFleetWorkloadInvalid(t *testing.T, err error, message string) {
	t.Helper()
	require.True(t, apierrors.IsInvalid(err), "expected admission rejection containing %q, got %v", message, err)
	require.ErrorContains(t, err, message)
}

func setWorkloadName(t *testing.T, obj *unstructured.Unstructured, suffix string) {
	t.Helper()
	obj.SetName("fleet-workload-" + suffix)
}

func setModule(t *testing.T, obj *unstructured.Unstructured, class, name string, module map[string]any) {
	t.Helper()
	require.NoError(t, unstructured.SetNestedMap(obj.Object, module, "spec", class, name))
}

func externalModule(realizationType string) map[string]any {
	return map[string]any{
		"type":               realizationType,
		"delivery":           "external",
		"providerAccountRef": "prod-account",
		"credentialMode":     "standard",
		"rotation":           "on",
		"engine":             map[string]any{realizationType: map[string]any{}},
	}
}

// TestFleetWorkloadSchemaAcceptsExactlySixValidFixtures is deliberately
// count-pinned so an empty or truncated fixture table cannot pass silently.
func TestFleetWorkloadSchemaAcceptsExactlySixValidFixtures(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)

	fixtures := []string{
		"platformdependency-valid.yaml",
		"virtuallandscapeservice-valid.yaml",
		"webhookengine-valid.yaml",
		"webhookroute-valid.yaml",
		"cloudflaredeploy-valid.yaml",
		"decommission-valid.yaml",
	}
	require.Len(t, fixtures, fleetWorkloadFixtureCount)

	for _, fixture := range fixtures {
		t.Run(fixture, func(t *testing.T) {
			createFleetWorkloadFixture(t, c, loadFleetWorkloadFixture(t, fixture))
		})
	}
}

// TestFleetWorkloadSchemaRejectsExactlySixInvalidFixtures proves that every
// kind has a non-vacuous invalid witness, independently of generated output.
func TestFleetWorkloadSchemaRejectsExactlySixInvalidFixtures(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)

	fixtures := []string{
		"platformdependency-invalid.yaml",
		"virtuallandscapeservice-invalid.yaml",
		"webhookengine-invalid.yaml",
		"webhookroute-invalid.yaml",
		"cloudflaredeploy-invalid.yaml",
		"decommission-invalid.yaml",
	}
	require.Len(t, fixtures, fleetWorkloadFixtureCount)

	for _, fixture := range fixtures {
		t.Run(fixture, func(t *testing.T) {
			obj := loadFleetWorkloadFixture(t, fixture)
			err := c.Create(context.Background(), obj)
			t.Cleanup(func() { _ = c.Delete(context.Background(), obj) })
			require.True(t, apierrors.IsInvalid(err), "expected a schema rejection, got %v", err)
		})
	}
}

// TestFleetWorkloadSchemaServesExactShape reads the CRDs back from the API
// server. It pins group, namespaced scope, short names, columns, status, and
// map-keyed conditions rather than trusting the Go markers that generated it.
func TestFleetWorkloadSchemaServesExactShape(t *testing.T) {
	c := newFleetClient(t)

	expectedKinds := []struct {
		crd       string
		shortName string
		columns   []string
	}{
		{"platformdependencies.fleet.atomi.cloud", "pdep", []string{"Platform", "Landscape", "Ready", "Age"}},
		{"virtuallandscapeservices.fleet.atomi.cloud", "vls", []string{"VLandscape", "Landscape", "Serve", "Ready", "Age"}},
		{"webhookengines.fleet.atomi.cloud", "wheng", []string{"Home", "Ready", "Age"}},
		{"webhookroutes.fleet.atomi.cloud", "whr", []string{"Engine", "Provider", "Path", "Ready", "Age"}},
		{"cloudflaredeploys.fleet.atomi.cloud", "cfd", []string{"Script", "Live", "Complete", "Age"}},
		{"decommissions.fleet.atomi.cloud", "decom", []string{"Kind", "Target", "Deleted", "Age"}},
	}
	require.Len(t, expectedKinds, fleetWorkloadFixtureCount)

	for _, expected := range expectedKinds {
		t.Run(expected.crd, func(t *testing.T) {
			crd := getFleetCRD(t, c, expected.crd)
			require.Equal(t, "fleet.atomi.cloud", crd.Object["spec"].(map[string]any)["group"])

			scope, found, err := unstructured.NestedString(crd.Object, "spec", "scope")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, "Namespaced", scope)

			shortNames, found, err := unstructured.NestedStringSlice(crd.Object, "spec", "names", "shortNames")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, []string{expected.shortName}, shortNames)

			versions, found, err := unstructured.NestedSlice(crd.Object, "spec", "versions")
			require.NoError(t, err)
			require.True(t, found)
			require.Len(t, versions, 1)
			version, ok := versions[0].(map[string]any)
			require.True(t, ok)
			require.Equal(t, "v1alpha1", version["name"])
			require.Equal(t, true, version["served"])
			require.Equal(t, expected.columns, printColumnNames(t, version))

			_, found, err = unstructured.NestedMap(version, "subresources", "status")
			require.NoError(t, err)
			require.True(t, found)
			requireStatusConditionsMap(t, version, "status", "conditions")
		})
	}
}

func requireStatusConditionsMap(t *testing.T, version map[string]any, path ...string) {
	t.Helper()
	base := []string{"schema", "openAPIV3Schema", "properties"}
	for i, segment := range path {
		base = append(base, segment)
		if i < len(path)-1 {
			base = append(base, "properties")
		}
	}
	listType, found, err := unstructured.NestedString(version, append(base, "x-kubernetes-list-type")...)
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "map", listType)
	keys, found, err := unstructured.NestedStringSlice(version, append(base, "x-kubernetes-list-map-keys")...)
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, []string{"type"}, keys)
}

// TestFleetWorkloadSchemaKeepsModuleStatusMapsRoundTrippable proves that
// module conditions stay isolated by module key and by condition type.
func TestFleetWorkloadSchemaKeepsModuleStatusMapsRoundTrippable(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	dependencyFixture := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
	setWorkloadName(t, dependencyFixture, "module-status")
	createFleetWorkloadFixture(t, c, dependencyFixture)

	var dependency fleetv1alpha1.PlatformDependency
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(dependencyFixture), &dependency))
	dependency.Status.Modules = map[string]fleetv1alpha1.PlatformDependencyModuleStatus{
		"maindb": {Phase: "ready", Conditions: []metav1.Condition{fleetCondition("Provisioned"), fleetCondition("Ready")}},
		"hot":    {Phase: "ready", Conditions: []metav1.Condition{fleetCondition("SecretWritten"), fleetCondition("Ready")}},
	}
	dependency.Status.Conditions = []metav1.Condition{fleetCondition("Ready")}
	dependency.Status.ObservedGeneration = dependency.Generation
	require.NoError(t, c.Status().Update(ctx, &dependency))

	var storedDependency fleetv1alpha1.PlatformDependency
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(&dependency), &storedDependency))
	require.Len(t, storedDependency.Status.Modules, 2)
	require.Equal(t, "ready", storedDependency.Status.Modules["maindb"].Phase)
	require.Len(t, storedDependency.Status.Modules["maindb"].Conditions, 2)
	require.Equal(t, "ready", storedDependency.Status.Modules["hot"].Phase)
	require.Len(t, storedDependency.Status.Modules["hot"].Conditions, 2)

	vlsFixture := loadFleetWorkloadFixture(t, "virtuallandscapeservice-valid.yaml")
	setWorkloadName(t, vlsFixture, "vls-module-status")
	createFleetWorkloadFixture(t, c, vlsFixture)
	var serve fleetv1alpha1.VirtualLandscapeService
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(vlsFixture), &serve))
	serve.Status.Host = "api.lithium.nitroso.mew.cluster.atomi.cloud"
	serve.Status.Modules = map[string]fleetv1alpha1.VirtualLandscapeServiceModuleStatus{
		"api": {Host: serve.Status.Host, Conditions: []metav1.Condition{fleetCondition("Accepted"), fleetCondition("Ready")}},
	}
	serve.Status.Conditions = []metav1.Condition{fleetCondition("RecordPublished"), fleetCondition("Ready")}
	require.NoError(t, c.Status().Update(ctx, &serve))

	var storedServe fleetv1alpha1.VirtualLandscapeService
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(&serve), &storedServe))
	require.Equal(t, "api.lithium.nitroso.mew.cluster.atomi.cloud", storedServe.Status.Host)
	require.Len(t, storedServe.Status.Modules, 1)
	require.Len(t, storedServe.Status.Modules["api"].Conditions, 2)

	storedDependency.Status.Modules["maindb"] = fleetv1alpha1.PlatformDependencyModuleStatus{
		Conditions: []metav1.Condition{fleetCondition("Ready"), fleetCondition("Ready")},
	}
	err := c.Status().Update(ctx, &storedDependency)
	require.True(t, apierrors.IsInvalid(err), "duplicate condition types inside one module must be rejected: %v", err)
}

// TestFleetWorkloadSchemaPlatformDependencyCELWitnesses names every admission
// rule on the module core and landscape support matrix.
func TestFleetWorkloadSchemaPlatformDependencyCELWitnesses(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	t.Run("engine key equals type", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
		setWorkloadName(t, obj, "cel-engine-key")
		require.NoError(t, unstructured.SetNestedMap(obj.Object, map[string]any{"upstash": map[string]any{}},
			"spec", "database", "maindb", "engine"))
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "exactly one engine key must be present and equal type")
	})

	t.Run("delivery legality", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
		setWorkloadName(t, obj, "cel-delivery")
		require.NoError(t, unstructured.SetNestedField(obj.Object, "local", "spec", "database", "maindb", "delivery"))
		unstructured.RemoveNestedField(obj.Object, "spec", "database", "maindb", "providerAccountRef")
		unstructured.RemoveNestedField(obj.Object, "spec", "database", "maindb", "account")
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "delivery is not legal for the selected type")
	})

	t.Run("external account required", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
		setWorkloadName(t, obj, "cel-provider-account")
		unstructured.RemoveNestedField(obj.Object, "spec", "database", "maindb", "providerAccountRef")
		unstructured.RemoveNestedField(obj.Object, "spec", "database", "maindb", "account")
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "external modules require providerAccountRef")
	})

	t.Run("account spellings agree", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
		setWorkloadName(t, obj, "cel-account-alias")
		require.NoError(t, unstructured.SetNestedField(obj.Object, "other-neon", "spec", "database", "maindb", "account", "name"))
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "account.name and providerAccountRef must agree")
	})

	t.Run("landscape by type matrix", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "platformdependency-invalid.yaml")
		setWorkloadName(t, obj, "cel-landscape-matrix")
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "module type is not supported by the target landscape")
	})
}

// TestFleetWorkloadSchemaPlatformDependencyClassCELWitnesses pins every class
// map restriction. Each error must name its own class rule even though the
// broader landscape matrix also rejects the deliberately crossed type.
func TestFleetWorkloadSchemaPlatformDependencyClassCELWitnesses(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	for _, witness := range []struct {
		class    string
		module   string
		typeName string
		message  string
	}{
		{"database", "maindb", "upstash", "database modules must use a database type"},
		{"kv", "sessions", "neon", "kv modules must use a kv type"},
		{"cache", "hot", "neon", "cache modules must use dragonfly"},
		{"store", "assets", "neon", "store modules must use a store type"},
		{"email", "sender", "neon", "email modules must use an email type"},
	} {
		t.Run(witness.class, func(t *testing.T) {
			obj := loadFleetWorkloadFixture(t, "platformdependency-valid.yaml")
			setWorkloadName(t, obj, "cel-class-"+witness.class)
			setModule(t, obj, witness.class, witness.module, externalModule(witness.typeName))
			requireFleetWorkloadInvalid(t, c.Create(ctx, obj), witness.message)
		})
	}
}

// TestFleetWorkloadSchemaAcceptsRuledLandscapeMatrixExamples checks one local
// parity module and one preview fork, complementing the production fixture.
func TestFleetWorkloadSchemaAcceptsRuledLandscapeMatrixExamples(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	local := loadFleetWorkloadFixture(t, "platformdependency-invalid.yaml")
	setWorkloadName(t, local, "matrix-local")
	require.NoError(t, unstructured.SetNestedField(local.Object, "lapras", "spec", "landscape"))
	require.NoError(t, unstructured.SetNestedField(local.Object, "lapras", "spec", "placement", "preferredHost"))
	require.NoError(t, c.Create(ctx, local))
	t.Cleanup(func() { _ = c.Delete(ctx, local) })

	preview := loadFleetWorkloadFixture(t, "platformdependency-invalid.yaml")
	setWorkloadName(t, preview, "matrix-preview")
	require.NoError(t, unstructured.SetNestedField(preview.Object, "plusle", "spec", "landscape"))
	require.NoError(t, unstructured.SetNestedField(preview.Object, "plusle", "spec", "placement", "preferredHost"))
	setModule(t, preview, "database", "maindb", map[string]any{
		"type":               "neon-fork",
		"delivery":           "external",
		"providerAccountRef": "preview-neon",
		"credentialMode":     "standard",
		"rotation":           "off",
		"engine": map[string]any{"neon-fork": map[string]any{
			"ttl": "168h",
			"parent": map[string]any{
				"platform": "nitroso", "landscape": "raichu", "service": "zinc", "module": "maindb",
			},
		}},
	})
	require.NoError(t, c.Create(ctx, preview))
	t.Cleanup(func() { _ = c.Delete(ctx, preview) })
}

// TestFleetWorkloadSchemaRemainingCELWitnesses pins transition/config rules on
// the other workload kinds.
func TestFleetWorkloadSchemaRemainingCELWitnesses(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	t.Run("WebhookEngine immutable home", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "webhookengine-valid.yaml")
		setWorkloadName(t, obj, "cel-home")
		createFleetWorkloadFixture(t, c, obj)
		require.NoError(t, unstructured.SetNestedField(obj.Object, "suicune", "spec", "home", "vlandscape"))
		requireFleetWorkloadInvalid(t, c.Update(ctx, obj), "home.vlandscape is immutable")
	})

	t.Run("Cloudflare exactly one version source", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "cloudflaredeploy-invalid.yaml")
		setWorkloadName(t, obj, "cel-version-source")
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "exactly one of desiredVersion or desiredVersionFrom is required")
	})

	t.Run("Cloudflare rollout reaches 100 percent", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "cloudflaredeploy-valid.yaml")
		setWorkloadName(t, obj, "cel-rollout-complete")
		require.NoError(t, unstructured.SetNestedSlice(obj.Object, []any{map[string]any{"percent": int64(10), "soak": "10m"}},
			"spec", "rollout", "steps"))
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "rollout steps must contain a 100 percent step")
	})

	t.Run("Decommission confirm friction", func(t *testing.T) {
		obj := loadFleetWorkloadFixture(t, "decommission-invalid.yaml")
		setWorkloadName(t, obj, "cel-confirm")
		requireFleetWorkloadInvalid(t, c.Create(ctx, obj), "confirm must exactly match targetRef.name")
	})
}

// TestFleetWorkloadSchemaDoesNotStealDerivedOrMercuryFields asserts absence,
// not merely omission from fixtures. Unknown fields are pruned, so there is no
// served schema home for derived host or mercury-owned runtime/deployment data.
func TestFleetWorkloadSchemaDoesNotStealDerivedOrMercuryFields(t *testing.T) {
	c := newFleetClient(t)

	assertSpecFieldsAbsent := func(t *testing.T, crdName string, forbidden ...string) {
		t.Helper()
		crd := getFleetCRD(t, c, crdName)
		versions, found, err := unstructured.NestedSlice(crd.Object, "spec", "versions")
		require.NoError(t, err)
		require.True(t, found)
		require.Len(t, versions, 1)
		version, ok := versions[0].(map[string]any)
		require.True(t, ok)
		properties, found, err := unstructured.NestedMap(version,
			"schema", "openAPIV3Schema", "properties", "spec", "properties")
		require.NoError(t, err)
		require.True(t, found)
		for _, field := range forbidden {
			require.NotContains(t, properties, field)
		}
	}

	assertSpecFieldsAbsent(t, "virtuallandscapeservices.fleet.atomi.cloud", "host")
	assertSpecFieldsAbsent(t, "webhookengines.fleet.atomi.cloud",
		"worker", "d1", "kv", "version", "engineVersion", "desiredVersion", "deployment")
	assertSpecFieldsAbsent(t, "webhookroutes.fleet.atomi.cloud", "url", "landscape", "worker")
}

// TestFleetWorkloadSchemaUnknownProviderRemainsReconcileTime proves admission
// does not pretend to know mercury's shipped adapter registry.
func TestFleetWorkloadSchemaUnknownProviderRemainsReconcileTime(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	obj := loadFleetWorkloadFixture(t, "webhookroute-valid.yaml")
	setWorkloadName(t, obj, "unknown-provider")
	require.NoError(t, unstructured.SetNestedField(obj.Object, "future-provider", "spec", "provider"))
	unstructured.RemoveNestedField(obj.Object, "spec", "scheme")
	createFleetWorkloadFixture(t, c, obj)
}
