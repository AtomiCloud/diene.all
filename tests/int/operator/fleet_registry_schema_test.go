package operator_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"

	fleetv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/fleet/v1alpha1"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/provideraccount"
)

// fleetRegistryNamespace is where the two namespaced registry kinds land. The
// platform home renders both into the platform's own namespace.
const fleetRegistryNamespace = "nitroso"

// newFleetClient builds a scheme LOCAL to this test. The registry API lane
// deliberately does not register its kinds in the manager's scheme: nothing in
// the binary reconciles them yet, and a schema test must not need it to.
func newFleetClient(t *testing.T) client.Client {
	t.Helper()
	local := runtime.NewScheme()
	require.NoError(t, clientgoscheme.AddToScheme(local))
	require.NoError(t, fleetv1alpha1.AddToScheme(local))
	built, err := client.New(restConfig, client.Options{Scheme: local})
	require.NoError(t, err)
	return built
}

func loadFleetFixture(t *testing.T, name string) *unstructured.Unstructured {
	t.Helper()
	//nolint:gosec // The fixture name is a test-local literal under the repository's own fixture directory.
	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "operator", "fleet", "registry", name))
	require.NoError(t, err)
	converted, err := utilyaml.ToJSON(raw)
	require.NoError(t, err)
	obj := &unstructured.Unstructured{}
	require.NoError(t, obj.UnmarshalJSON(converted))
	return obj
}

func ensureFleetNamespace(t *testing.T, c client.Client) {
	t.Helper()
	err := c.Create(context.Background(), &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: fleetRegistryNamespace},
	})
	require.True(t, err == nil || apierrors.IsAlreadyExists(err), "create fixture namespace: %v", err)
}

func fleetCondition(conditionType string) metav1.Condition {
	return metav1.Condition{
		Type:               conditionType,
		Status:             metav1.ConditionTrue,
		Reason:             "SchemaTest",
		Message:            "written by the registry schema test",
		LastTransitionTime: metav1.Now(),
	}
}

func getFleetCRD(t *testing.T, c client.Client, name string) *unstructured.Unstructured {
	t.Helper()
	crd := &unstructured.Unstructured{}
	crd.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "apiextensions.k8s.io",
		Version: "v1",
		Kind:    "CustomResourceDefinition",
	})
	require.NoError(t, c.Get(context.Background(), client.ObjectKey{Name: name}, crd))
	return crd
}

// TestFleetRegistrySchemaGroupVersionMatchesConsumerContract pins the group
// string. It is a DISCOVERED consumer contract: the platform home's primordial
// chart and every service primordial chart already render these kinds at this
// apiVersion, so the constant is asserted here rather than trusted.
func TestFleetRegistrySchemaGroupVersionMatchesConsumerContract(t *testing.T) {
	require.Equal(t, "fleet.atomi.cloud", fleetv1alpha1.Group)
	require.Equal(t, "v1alpha1", fleetv1alpha1.Version)
	require.Equal(t, "fleet.atomi.cloud/v1alpha1", fleetv1alpha1.GroupVersion.String())
}

func TestFleetRegistrySchemaAcceptsValidFixtures(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)

	for _, fixture := range []string{
		"landscape-valid.yaml",
		"clusterregistration-valid.yaml",
		"virtuallandscape-valid.yaml",
		"platform-valid.yaml",
		"provideraccount-valid.yaml",
	} {
		t.Run(fixture, func(t *testing.T) {
			obj := loadFleetFixture(t, fixture)
			require.NoError(t, c.Create(context.Background(), obj))
			t.Cleanup(func() { _ = c.Delete(context.Background(), obj) })
		})
	}
}

func TestFleetRegistrySchemaRejectsInvalidFixtures(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)

	for _, fixture := range []string{
		"landscape-invalid.yaml",
		"clusterregistration-invalid.yaml",
		"virtuallandscape-invalid.yaml",
		"platform-invalid.yaml",
		"provideraccount-invalid.yaml",
	} {
		t.Run(fixture, func(t *testing.T) {
			obj := loadFleetFixture(t, fixture)
			err := c.Create(context.Background(), obj)
			t.Cleanup(func() { _ = c.Delete(context.Background(), obj) })
			require.True(t, apierrors.IsInvalid(err), "expected a schema rejection, got %v", err)
		})
	}
}

// TestFleetRegistrySchemaServesRegistryShape asserts the shape every served
// registry kind must carry: its scope, its short name, a status subresource,
// its print columns, and map-keyed status conditions. The CRDs are read back
// from the API server, so this checks what is actually SERVED rather than what
// the Go markers claim.
func TestFleetRegistrySchemaServesRegistryShape(t *testing.T) {
	c := newFleetClient(t)

	for _, expected := range []struct {
		crd       string
		scope     string
		shortName string
		columns   []string
	}{
		{"landscapes.fleet.atomi.cloud", "Cluster", "lsc", []string{"Region", "Tier", "Purpose", "Age"}},
		{
			"clusterregistrations.fleet.atomi.cloud", "Cluster", "creg",
			[]string{"Landscape", "Provider", "Traffic", "Phase", "Accepting", "Age"},
		},
		{"virtuallandscapes.fleet.atomi.cloud", "Cluster", "vlsc", []string{"Hosts", "Age"}},
		{"platforms.fleet.atomi.cloud", "Namespaced", "plat", []string{"Project", "Ready", "Age"}},
		{
			"provideraccounts.fleet.atomi.cloud", "Namespaced", "pacct",
			[]string{"Vendor", "Account", "Plan", "Age"},
		},
	} {
		t.Run(expected.crd, func(t *testing.T) {
			crd := getFleetCRD(t, c, expected.crd)

			scope, found, err := unstructured.NestedString(crd.Object, "spec", "scope")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, expected.scope, scope)

			shortNames, found, err := unstructured.NestedStringSlice(crd.Object, "spec", "names", "shortNames")
			require.NoError(t, err)
			require.True(t, found)
			require.Contains(t, shortNames, expected.shortName)

			versions, found, err := unstructured.NestedSlice(crd.Object, "spec", "versions")
			require.NoError(t, err)
			require.True(t, found)
			require.Len(t, versions, 1)
			version, ok := versions[0].(map[string]any)
			require.True(t, ok)

			_, found, err = unstructured.NestedMap(version, "subresources", "status")
			require.NoError(t, err)
			require.True(t, found, "served kind has no status subresource")

			require.Equal(t, expected.columns, printColumnNames(t, version))

			listType, found, err := unstructured.NestedString(version,
				"schema", "openAPIV3Schema", "properties", "status", "properties", "conditions",
				"x-kubernetes-list-type")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, "map", listType)

			listMapKeys, found, err := unstructured.NestedStringSlice(version,
				"schema", "openAPIV3Schema", "properties", "status", "properties", "conditions",
				"x-kubernetes-list-map-keys")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, []string{"type"}, listMapKeys)
		})
	}
}

func printColumnNames(t *testing.T, version map[string]any) []string {
	t.Helper()
	columns, found, err := unstructured.NestedSlice(version, "additionalPrinterColumns")
	require.NoError(t, err)
	require.True(t, found, "served kind has no print columns")
	names := make([]string, 0, len(columns))
	for _, raw := range columns {
		column, ok := raw.(map[string]any)
		require.True(t, ok)
		name, ok := column["name"].(string)
		require.True(t, ok)
		names = append(names, name)
	}
	return names
}

// TestFleetRegistrySchemaIsolatesStatusAsAMapList proves the two properties the
// condition vocabulary depends on: status is a real subresource, so a spec
// write can never carry status with it, and conditions are keyed by type, so
// one condition can never silently overwrite another.
func TestFleetRegistrySchemaIsolatesStatusAsAMapList(t *testing.T) {
	c := newFleetClient(t)
	ctx := context.Background()

	landscape := &fleetv1alpha1.Landscape{
		ObjectMeta: metav1.ObjectMeta{Name: "fleet-registry-status"},
		Spec:       fleetv1alpha1.LandscapeSpec{Region: "ap-southeast-1", Tier: "prod"},
	}
	require.NoError(t, c.Create(ctx, landscape))
	t.Cleanup(func() { _ = c.Delete(ctx, landscape) })

	landscape.Status.ObservedGeneration = 7
	landscape.Status.Conditions = []metav1.Condition{fleetCondition("Ready")}
	require.NoError(t, c.Update(ctx, landscape))

	var afterSpecWrite fleetv1alpha1.Landscape
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(landscape), &afterSpecWrite))
	require.Zero(t, afterSpecWrite.Status.ObservedGeneration)
	require.Empty(t, afterSpecWrite.Status.Conditions)

	afterSpecWrite.Status.ObservedGeneration = afterSpecWrite.Generation
	afterSpecWrite.Status.Conditions = []metav1.Condition{fleetCondition("Ready"), fleetCondition("Drifted")}
	require.NoError(t, c.Status().Update(ctx, &afterSpecWrite))

	var afterStatusWrite fleetv1alpha1.Landscape
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(landscape), &afterStatusWrite))
	require.Len(t, afterStatusWrite.Status.Conditions, 2)
	require.Equal(t, afterStatusWrite.Generation, afterStatusWrite.Status.ObservedGeneration)

	afterStatusWrite.Status.Conditions = []metav1.Condition{fleetCondition("Ready"), fleetCondition("Ready")}
	err := c.Status().Update(ctx, &afterStatusWrite)
	require.True(t, apierrors.IsInvalid(err), "expected duplicate condition types to be rejected, got %v", err)
}

// TestFleetRegistrySchemaRefusesLandscapeRegionChange exercises the one CEL
// transition rule in this lane. A landscape's region is load-bearing for
// placement, so moving it must fail at admission rather than silently re-home
// live externals.
func TestFleetRegistrySchemaRefusesLandscapeRegionChange(t *testing.T) {
	c := newFleetClient(t)
	ctx := context.Background()

	landscape := &fleetv1alpha1.Landscape{
		ObjectMeta: metav1.ObjectMeta{Name: "fleet-registry-immutable-region"},
		Spec:       fleetv1alpha1.LandscapeSpec{Region: "ap-southeast-1"},
	}
	require.NoError(t, c.Create(ctx, landscape))
	t.Cleanup(func() { _ = c.Delete(ctx, landscape) })

	landscape.Spec.Region = "us-east-1"
	err := c.Update(ctx, landscape)
	require.True(t, apierrors.IsInvalid(err), "expected an immutable-region rejection, got %v", err)

	landscape.Spec.Region = "ap-southeast-1"
	landscape.Spec.Tier = "staging"
	require.NoError(t, c.Update(ctx, landscape), "an unrelated spec edit must still be accepted")
}

// TestFleetRegistrySchemaPreservesPipelineStepForms proves the promotion DAG
// survives a round trip through the API server in every step form the platform
// home may author — a bare landscape name, an object step, and a parallel set.
// Pruning any of them would silently drop promotion semantics.
func TestFleetRegistrySchemaPreservesPipelineStepForms(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	platform := loadFleetFixture(t, "platform-valid.yaml")
	platform.SetName("fleet-registry-pipeline")
	require.NoError(t, c.Create(ctx, platform))
	t.Cleanup(func() { _ = c.Delete(ctx, platform) })

	stored := &unstructured.Unstructured{}
	stored.SetGroupVersionKind(platform.GroupVersionKind())
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(platform), stored))

	stages, found, err := unstructured.NestedSlice(stored.Object, "spec", "pipeline", "stages")
	require.NoError(t, err)
	require.True(t, found)
	require.Len(t, stages, 3)

	require.Equal(t, "pichu", stages[0])
	require.Equal(t, map[string]any{"landscape": "pikachu", "gate": "manual", "soak": "30m"}, stages[1])
	require.Equal(t, []any{"raichu", "amphoros"}, stages[2])
}

// TestFleetRegistrySchemaProviderAccountCarriesNoCredential proves the two
// properties the S2 review repair requires. A ProviderAccount names a
// vendor/account context only: any credential object supplied on the spec has no
// served home, because the structural CRD carries no such property and the API
// server prunes it. And the sole canonical credential address is the one the F4
// resolver DERIVES from a consuming module's runtime coordinate plus this
// account's vendor/name — asserted through the published constructor so the
// address is pinned here without this test re-implementing the pointer grammar.
func TestFleetRegistrySchemaProviderAccountCarriesNoCredential(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	// A credential source AND path are both supplied; neither survives to served
	// state, so the CR cannot become a second source of truth for credentials.
	withCredential := loadFleetFixture(t, "provideraccount-valid.yaml")
	withCredential.SetName("fleet-registry-account-credential")
	require.NoError(t, unstructured.SetNestedField(withCredential.Object,
		"infisical", "spec", "credential", "source"))
	require.NoError(t, unstructured.SetNestedField(withCredential.Object,
		"/forged/unrelated/path", "spec", "credential", "path"))
	require.NoError(t, c.Create(ctx, withCredential))
	t.Cleanup(func() { _ = c.Delete(ctx, withCredential) })

	stored := &unstructured.Unstructured{}
	stored.SetGroupVersionKind(withCredential.GroupVersionKind())
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(withCredential), stored))

	_, found, err := unstructured.NestedFieldNoCopy(stored.Object, "spec", "credential")
	require.NoError(t, err)
	require.False(t, found, "the schema must leave no served home for a credential source or path")

	// The one legitimate credential address is derived from the runtime
	// coordinate (platform/landscape/class) plus the account's vendor/name.
	vendor, found, err := unstructured.NestedString(stored.Object, "spec", "vendor")
	require.NoError(t, err)
	require.True(t, found)
	name, found, err := unstructured.NestedString(stored.Object, "spec", "name")
	require.NoError(t, err)
	require.True(t, found)

	pointer, err := provideraccount.CredentialPointerPath("nitroso", "raichu", "database", vendor, name)
	require.NoError(t, err)
	require.Equal(t, "/nitroso/raichu/database/neon-account-prod", pointer,
		"the sole canonical pointer is F4-derived, never read from the CR")
}

// TestFleetRegistrySchemaKeepsAccountNameDomainOpen is a regression guard from
// the F4 review. A DNS-label-valid account name that happens to contain the
// reserved "account" delimiter token — "account-prod" here — must stay
// schema-valid: the registry CRD keeps vendor/name the full DNS-label charset
// and never narrows it to dodge the derived-pointer grammar. Keeping the derived
// pointer injective for such names is the separately owned F4 mapping. This
// cross-boundary witness therefore proves both halves against the object the API
// server actually accepted: S2 keeps the name and F4 derives its escaped path.
func TestFleetRegistrySchemaKeepsAccountNameDomainOpen(t *testing.T) {
	c := newFleetClient(t)
	ensureFleetNamespace(t, c)
	ctx := context.Background()

	account := loadFleetFixture(t, "provideraccount-valid.yaml")
	account.SetName("fleet-registry-account-token-name")
	require.NoError(t, unstructured.SetNestedField(account.Object, "account-prod", "spec", "name"))
	require.NoError(t, c.Create(ctx, account),
		"a DNS-label name containing the reserved \"account\" token must remain accepted")
	t.Cleanup(func() { _ = c.Delete(ctx, account) })

	stored := &unstructured.Unstructured{}
	stored.SetGroupVersionKind(account.GroupVersionKind())
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(account), stored))
	vendor, found, err := unstructured.NestedString(stored.Object, "spec", "vendor")
	require.NoError(t, err)
	require.True(t, found)
	name, found, err := unstructured.NestedString(stored.Object, "spec", "name")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "account-prod", name)

	pointer, err := provideraccount.CredentialPointerPath("nitroso", "raichu", "database", vendor, name)
	require.NoError(t, err)
	require.Equal(t, "/nitroso/raichu/database/_pa_neon_account-prod", pointer)
}
