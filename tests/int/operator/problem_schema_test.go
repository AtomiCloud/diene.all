package operator_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"

	fleetv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/fleet/v1alpha1"
	problemsv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/problems/v1alpha1"
)

const (
	// problemNamespace is the platform-scoped home for Problem rows. The
	// namespace == platform convention is documented but NOT structurally
	// enforced, so the fixtures simply use it.
	problemNamespace = "nitroso"

	// problemCRDName is the plural.group CRD NAME. It is deliberately not the
	// API group: the group is atomi.cloud.
	problemCRDName = "problems.atomi.cloud"

	problemValidFixtureCount   = 2
	problemInvalidFixtureCount = 7
	problemCELWitnessCount     = 5

	celWitnessRootName           = "root-name"
	celWitnessPlatformImmutable  = "platform-immutable"
	celWitnessServiceImmutable   = "service-immutable"
	celWitnessLandscapeImmutable = "landscape-immutable"
	celWitnessVersionImmutable   = "version-immutable"

	messageRootName           = "name must be {service}-{landscape}-{version}"
	messagePlatformImmutable  = "platform is immutable"
	messageServiceImmutable   = "service is immutable"
	messageLandscapeImmutable = "landscape is immutable"
	messageVersionImmutable   = "version is immutable — a version bump is a new CR"
)

// newProblemClient builds a scheme LOCAL to this test, registering client-go and
// the Problem API only. Nothing in the binary reconciles Problem in Phase 2, so
// the manager's own scheme is deliberately not involved.
func newProblemClient(t *testing.T) client.Client {
	t.Helper()
	local := runtime.NewScheme()
	require.NoError(t, clientgoscheme.AddToScheme(local))
	require.NoError(t, problemsv1alpha1.AddToScheme(local))
	built, err := client.New(restConfig, client.Options{Scheme: local})
	require.NoError(t, err)
	return built
}

func loadProblemFixture(t *testing.T, name string) *unstructured.Unstructured {
	t.Helper()
	//nolint:gosec // The fixture name is a test-local literal under the repository's own fixture directory.
	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "operator", "problem", name))
	require.NoError(t, err)
	converted, err := utilyaml.ToJSON(raw)
	require.NoError(t, err)
	obj := &unstructured.Unstructured{}
	require.NoError(t, obj.UnmarshalJSON(converted))
	return obj
}

func ensureProblemNamespace(t *testing.T, c client.Client) {
	t.Helper()
	err := c.Create(context.Background(), &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: problemNamespace},
	})
	require.True(t, err == nil || apierrors.IsAlreadyExists(err), "create fixture namespace: %v", err)
}

func problemCondition(conditionType string) metav1.Condition {
	return metav1.Condition{
		Type:               conditionType,
		Status:             metav1.ConditionTrue,
		Reason:             "SchemaTest",
		Message:            "written by the Problem schema test",
		LastTransitionTime: metav1.Now(),
	}
}

func getProblemCRD(t *testing.T, c client.Client) *unstructured.Unstructured {
	t.Helper()
	crd := &unstructured.Unstructured{}
	crd.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "apiextensions.k8s.io",
		Version: "v1",
		Kind:    "CustomResourceDefinition",
	})
	require.NoError(t, c.Get(context.Background(), client.ObjectKey{Name: problemCRDName}, crd))
	return crd
}

func requireProblemInvalid(t *testing.T, err error, message string) {
	t.Helper()
	require.True(t, apierrors.IsInvalid(err), "expected admission rejection containing %q, got %v", message, err)
	require.ErrorContains(t, err, message)
}

// storeProblemRow creates a renamed copy of the primary valid fixture so each
// witness owns an independent live object to mutate.
func storeProblemRow(t *testing.T, c client.Client, service, landscape, version string) *unstructured.Unstructured {
	t.Helper()
	obj := loadProblemFixture(t, "problem-valid.yaml")
	obj.SetName(service + "-" + landscape + "-" + version)
	require.NoError(t, unstructured.SetNestedField(obj.Object, service, "spec", "service"))
	require.NoError(t, unstructured.SetNestedField(obj.Object, landscape, "spec", "landscape"))
	require.NoError(t, unstructured.SetNestedField(obj.Object, version, "spec", "version"))
	require.NoError(t, c.Create(context.Background(), obj))
	t.Cleanup(func() { _ = c.Delete(context.Background(), obj) })
	return obj
}

// TestProblemSchemaGroupIsOwnConstantAndNotInherited pins the ruled identity.
// The Problem group is atomi.cloud, declared by its own constant; the fleet group
// is never inherited, and problems.atomi.cloud is only the CRD NAME.
func TestProblemSchemaGroupIsOwnConstantAndNotInherited(t *testing.T) {
	require.Equal(t, "atomi.cloud", problemsv1alpha1.Group)
	require.Equal(t, "v1alpha1", problemsv1alpha1.Version)
	require.Equal(t, "atomi.cloud/v1alpha1", problemsv1alpha1.GroupVersion.String())

	require.NotEqual(t, fleetv1alpha1.Group, problemsv1alpha1.Group,
		"the Problem group must not be the fleet group")
	require.NotEqual(t, "fleet.atomi.cloud", problemsv1alpha1.Group)
	require.NotEqual(t, "problems.atomi.cloud", problemsv1alpha1.Group,
		"problems.atomi.cloud is the plural.group CRD NAME, never the API group")
}

// TestProblemSchemaServesRowShape asserts what the API server actually SERVES
// rather than what the Go markers claim.
func TestProblemSchemaServesRowShape(t *testing.T) {
	c := newProblemClient(t)
	crd := getProblemCRD(t, c)

	group, found, err := unstructured.NestedString(crd.Object, "spec", "group")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "atomi.cloud", group)

	scope, found, err := unstructured.NestedString(crd.Object, "spec", "scope")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "Namespaced", scope)

	kind, found, err := unstructured.NestedString(crd.Object, "spec", "names", "kind")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "Problem", kind)

	shortNames, found, err := unstructured.NestedStringSlice(crd.Object, "spec", "names", "shortNames")
	require.NoError(t, err)
	require.True(t, found)
	require.Contains(t, shortNames, "prb")

	versions, found, err := unstructured.NestedSlice(crd.Object, "spec", "versions")
	require.NoError(t, err)
	require.True(t, found)
	require.Len(t, versions, 1, "exactly one served version")
	version, ok := versions[0].(map[string]any)
	require.True(t, ok)
	require.Equal(t, "v1alpha1", version["name"])
	require.Equal(t, true, version["served"])
	require.Equal(t, true, version["storage"])

	_, found, err = unstructured.NestedMap(version, "subresources", "status")
	require.NoError(t, err)
	require.True(t, found, "served kind has no status subresource")

	require.Equal(t, []string{"Service", "Landscape", "Version", "Published", "Age"},
		printColumnNames(t, version))

	conditionsListType, found, err := unstructured.NestedString(version,
		"schema", "openAPIV3Schema", "properties", "status", "properties", "conditions",
		"x-kubernetes-list-type")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "map", conditionsListType)

	conditionsKeys, found, err := unstructured.NestedStringSlice(version,
		"schema", "openAPIV3Schema", "properties", "status", "properties", "conditions",
		"x-kubernetes-list-map-keys")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, []string{"type"}, conditionsKeys)

	problemsListType, found, err := unstructured.NestedString(version,
		"schema", "openAPIV3Schema", "properties", "spec", "properties", "problems",
		"x-kubernetes-list-type")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, "map", problemsListType)

	problemsKeys, found, err := unstructured.NestedStringSlice(version,
		"schema", "openAPIV3Schema", "properties", "spec", "properties", "problems",
		"x-kubernetes-list-map-keys")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, []string{"id"}, problemsKeys)
}

// TestProblemSchemaAcceptsBothValidFixtures is count-pinned so a truncated or
// empty fixture directory cannot pass silently. The empty row is a first-class
// state: a release that catalogues nothing must still be expressible.
func TestProblemSchemaAcceptsBothValidFixtures(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	fixtures := []struct {
		file       string
		service    string
		version    string
		entryCount int
	}{
		{"problem-valid.yaml", "zinc", "v1", 2},
		{"problem-empty-row-valid.yaml", "cobalt", "v2", 0},
	}
	require.Len(t, fixtures, problemValidFixtureCount)

	for _, fixture := range fixtures {
		t.Run(fixture.file, func(t *testing.T) {
			obj := loadProblemFixture(t, fixture.file)
			require.NoError(t, c.Create(ctx, obj))
			t.Cleanup(func() { _ = c.Delete(ctx, obj) })

			stored := &unstructured.Unstructured{}
			stored.SetGroupVersionKind(obj.GroupVersionKind())
			require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(obj), stored))

			platform, found, err := unstructured.NestedString(stored.Object, "spec", "platform")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, "nitroso", platform)

			service, found, err := unstructured.NestedString(stored.Object, "spec", "service")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, fixture.service, service)

			landscape, found, err := unstructured.NestedString(stored.Object, "spec", "landscape")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, "raichu", landscape)

			version, found, err := unstructured.NestedString(stored.Object, "spec", "version")
			require.NoError(t, err)
			require.True(t, found)
			require.Equal(t, fixture.version, version)

			entries, found, err := unstructured.NestedSlice(stored.Object, "spec", "problems")
			require.NoError(t, err)
			if fixture.entryCount == 0 {
				require.False(t, found, "an empty row must round-trip with no problems key")
				return
			}
			require.True(t, found)
			require.Len(t, entries, fixture.entryCount)
		})
	}
}

// TestProblemSchemaPreservesUnknownOnlyInsideSchema proves the boundary is an
// ISLAND: the whole schema object survives verbatim, including a key the CRD has
// never heard of and its nested structure, while an unknown field one level out
// is pruned.
func TestProblemSchemaPreservesUnknownOnlyInsideSchema(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	obj := loadProblemFixture(t, "problem-valid.yaml")
	authored, found, err := unstructured.NestedSlice(obj.Object, "spec", "problems")
	require.NoError(t, err)
	require.True(t, found)
	require.Len(t, authored, 2)

	require.NoError(t, c.Create(ctx, obj))
	t.Cleanup(func() { _ = c.Delete(ctx, obj) })

	stored := &unstructured.Unstructured{}
	stored.SetGroupVersionKind(obj.GroupVersionKind())
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(obj), stored))
	served, found, err := unstructured.NestedSlice(stored.Object, "spec", "problems")
	require.NoError(t, err)
	require.True(t, found)
	require.Len(t, served, 2)

	// INSIDE the boundary: every entry's whole schema object is deep-equal to
	// what was authored, vendor extension and nested keys included.
	for index := range served {
		authoredEntry, ok := authored[index].(map[string]any)
		require.True(t, ok)
		servedEntry, ok := served[index].(map[string]any)
		require.True(t, ok)
		require.Equal(t, authoredEntry["schema"], servedEntry["schema"],
			"the entire schema object must be preserved byte-for-byte")
	}

	firstServed, ok := served[0].(map[string]any)
	require.True(t, ok)
	firstSchema, ok := firstServed["schema"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, "preserved-verbatim", firstSchema["x-custom-annotation"],
		"an arbitrary non-JSON-Schema key must survive inside the island")
	require.Contains(t, firstSchema, "properties")
	require.Contains(t, firstSchema, "required")

	// OUTSIDE the boundary: an unknown entry field is accepted and pruned.
	mutated := loadProblemFixture(t, "problem-valid.yaml")
	mutated.SetName("zinc-pichu-v1")
	require.NoError(t, unstructured.SetNestedField(mutated.Object, "pichu", "spec", "landscape"))
	entries, found, err := unstructured.NestedSlice(mutated.Object, "spec", "problems")
	require.NoError(t, err)
	require.True(t, found)
	firstEntry, ok := entries[0].(map[string]any)
	require.True(t, ok)
	firstEntry["bogus"] = true
	require.NoError(t, unstructured.SetNestedSlice(mutated.Object, entries, "spec", "problems"))
	require.NoError(t, c.Create(ctx, mutated), "an unknown field outside the island is pruned, not rejected")
	t.Cleanup(func() { _ = c.Delete(ctx, mutated) })

	storedMutated := &unstructured.Unstructured{}
	storedMutated.SetGroupVersionKind(mutated.GroupVersionKind())
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(mutated), storedMutated))
	servedMutated, found, err := unstructured.NestedSlice(storedMutated.Object, "spec", "problems")
	require.NoError(t, err)
	require.True(t, found)
	firstMutated, ok := servedMutated[0].(map[string]any)
	require.True(t, ok)
	_, boundaryLeaked := firstMutated["bogus"]
	require.False(t, boundaryLeaked, "an unknown field outside spec.problems[*].schema must be pruned")
}

// TestProblemSchemaRejectsAllSevenInvalidFixtures gives every structural family
// a NAMED rejection witness, count-pinned so an empty fixture directory cannot
// pass.
func TestProblemSchemaRejectsAllSevenInvalidFixtures(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	fixtures := []string{
		"problem-invalid-name.yaml",
		"problem-invalid-version.yaml",
		"problem-invalid-id.yaml",
		"problem-invalid-status.yaml",
		"problem-invalid-type-uri.yaml",
		"problem-invalid-duplicate-id.yaml",
		"problem-invalid-missing-title.yaml",
	}
	require.Len(t, fixtures, problemInvalidFixtureCount)

	for _, fixture := range fixtures {
		t.Run(fixture, func(t *testing.T) {
			obj := loadProblemFixture(t, fixture)
			err := c.Create(ctx, obj)
			t.Cleanup(func() { _ = c.Delete(ctx, obj) })
			require.True(t, apierrors.IsInvalid(err), "expected a schema rejection, got %v", err)
		})
	}
}

// TestProblemSchemaRefusesIdentityFieldChanges witnesses all four immutability
// transitions on live objects and proves an unrelated in-place edit still works
// — re-materializing a row must stay possible.
func TestProblemSchemaRefusesIdentityFieldChanges(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	for _, transition := range []struct {
		name    string
		field   string
		value   string
		message string
	}{
		{"version v1 to v2", "version", "v2", messageVersionImmutable},
		{"platform", "platform", "boron", messagePlatformImmutable},
		{"service", "service", "cobalt", messageServiceImmutable},
		{"landscape", "landscape", "pichu", messageLandscapeImmutable},
	} {
		t.Run(transition.name, func(t *testing.T) {
			obj := storeProblemRow(t, c, "zinc", "raichu", "v1")
			live := &unstructured.Unstructured{}
			live.SetGroupVersionKind(obj.GroupVersionKind())
			require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(obj), live))
			require.NoError(t, unstructured.SetNestedField(live.Object, transition.value, "spec", transition.field))
			requireProblemInvalid(t, c.Update(ctx, live), transition.message)
		})
	}

	t.Run("unrelated in-place edit is accepted", func(t *testing.T) {
		obj := storeProblemRow(t, c, "zinc", "amphoros", "v1")
		live := &unstructured.Unstructured{}
		live.SetGroupVersionKind(obj.GroupVersionKind())
		require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(obj), live))
		entries, found, err := unstructured.NestedSlice(live.Object, "spec", "problems")
		require.NoError(t, err)
		require.True(t, found)
		entry, ok := entries[0].(map[string]any)
		require.True(t, ok)
		entry["title"] = "Entity Not Found (revised)"
		require.NoError(t, unstructured.SetNestedSlice(live.Object, entries, "spec", "problems"))
		require.NoError(t, c.Update(ctx, live), "an unrelated spec edit must still be accepted")
	})
}

// TestProblemSchemaPinsFiveCELRules is the count-pinned witness table AND the
// exact served-rule set. Every witness executes a real API-server call and
// asserts its exact CEL message; independently, every x-kubernetes-validations
// row beneath the served openAPIV3Schema is collected, normalized to
// (schema path, rule, message), and asserted set-equal to the same five tuples.
func TestProblemSchemaPinsFiveCELRules(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	immutableWitness := func(field, landscape, value, message string) func(*testing.T) {
		return func(t *testing.T) {
			obj := storeProblemRow(t, c, "zinc", landscape, "v1")
			live := &unstructured.Unstructured{}
			live.SetGroupVersionKind(obj.GroupVersionKind())
			require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(obj), live))
			require.NoError(t, unstructured.SetNestedField(live.Object, value, "spec", field))
			requireProblemInvalid(t, c.Update(ctx, live), message)
		}
	}

	witnesses := []struct {
		name    string
		path    string
		rule    string
		message string
		reject  func(*testing.T)
	}{
		{
			celWitnessRootName, "$",
			"self.metadata.name == self.spec.service + '-' + self.spec.landscape + '-' + self.spec.version",
			messageRootName,
			func(t *testing.T) {
				obj := loadProblemFixture(t, "problem-invalid-name.yaml")
				requireProblemInvalid(t, c.Create(ctx, obj), messageRootName)
				t.Cleanup(func() { _ = c.Delete(ctx, obj) })
			},
		},
		{
			celWitnessPlatformImmutable, "$.properties.spec.properties.platform",
			"self == oldSelf", messagePlatformImmutable,
			immutableWitness("platform", "cel-platform", "boron", messagePlatformImmutable),
		},
		{
			celWitnessServiceImmutable, "$.properties.spec.properties.service",
			"self == oldSelf", messageServiceImmutable,
			immutableWitness("service", "cel-service", "cobalt", messageServiceImmutable),
		},
		{
			celWitnessLandscapeImmutable, "$.properties.spec.properties.landscape",
			"self == oldSelf", messageLandscapeImmutable,
			immutableWitness("landscape", "cel-landscape", "pichu", messageLandscapeImmutable),
		},
		{
			celWitnessVersionImmutable, "$.properties.spec.properties.version",
			"self == oldSelf", messageVersionImmutable,
			immutableWitness("version", "cel-version", "v2", messageVersionImmutable),
		},
	}

	require.Len(t, witnesses, problemCELWitnessCount)
	seen := make(map[string]struct{}, len(witnesses))
	expectedTuples := make(map[string]struct{}, len(witnesses))
	for _, witness := range witnesses {
		require.NotContains(t, seen, witness.name, "CEL witness names must be unique")
		seen[witness.name] = struct{}{}
		expectedTuples[witness.path+"|"+witness.rule+"|"+witness.message] = struct{}{}
		t.Run(witness.name, witness.reject)
	}
	require.Len(t, expectedTuples, problemCELWitnessCount)

	t.Run("served CRD carries exactly these five rules", func(t *testing.T) {
		crd := getProblemCRD(t, c)
		versions, found, err := unstructured.NestedSlice(crd.Object, "spec", "versions")
		require.NoError(t, err)
		require.True(t, found)
		require.Len(t, versions, 1)
		version, ok := versions[0].(map[string]any)
		require.True(t, ok)
		root, found, err := unstructured.NestedMap(version, "schema", "openAPIV3Schema")
		require.NoError(t, err)
		require.True(t, found)

		served := make(map[string]struct{})
		collectServedCEL(t, root, "$", served)

		require.Len(t, served, problemCELWitnessCount,
			"the served CRD must carry exactly five CEL rules and no extras")
		require.Equal(t, expectedTuples, served,
			"served (path, rule, message) tuples must equal the pinned witness table")
	})
}

// collectServedCEL walks the served OpenAPI schema and records every
// x-kubernetes-validations row as a normalized "path|rule|message" tuple, so an
// extra CEL rule anywhere in the tree is caught rather than assumed absent.
func collectServedCEL(t *testing.T, node map[string]any, path string, into map[string]struct{}) {
	t.Helper()

	if rules, found := node["x-kubernetes-validations"]; found {
		list, ok := rules.([]any)
		require.True(t, ok, "x-kubernetes-validations at %s is not a list", path)
		for _, raw := range list {
			rule, ok := raw.(map[string]any)
			require.True(t, ok)
			expression, ok := rule["rule"].(string)
			require.True(t, ok, "CEL row at %s has no rule", path)
			message, ok := rule["message"].(string)
			require.True(t, ok, "CEL row at %s has no message", path)
			into[path+"|"+expression+"|"+message] = struct{}{}
		}
	}

	for _, key := range []string{"properties", "definitions"} {
		children, found := node[key]
		if !found {
			continue
		}
		childMap, ok := children.(map[string]any)
		require.True(t, ok)
		for name, raw := range childMap {
			child, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			collectServedCEL(t, child, path+"."+key+"."+name, into)
		}
	}

	for _, key := range []string{"items", "additionalProperties", "not"} {
		child, found := node[key]
		if !found {
			continue
		}
		childMap, ok := child.(map[string]any)
		if !ok {
			continue
		}
		collectServedCEL(t, childMap, path+"."+key, into)
	}

	for _, key := range []string{"allOf", "anyOf", "oneOf"} {
		children, found := node[key]
		if !found {
			continue
		}
		list, ok := children.([]any)
		if !ok {
			continue
		}
		for _, raw := range list {
			child, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			collectServedCEL(t, child, path+"."+key, into)
		}
	}
}

// TestProblemSchemaIsolatesStatusAsAMapList proves the two properties the merge
// component's patch-on-delta status writes depend on: status is a real
// subresource, so a spec write can never carry status with it, and conditions
// are keyed by type, so one condition can never silently overwrite another.
func TestProblemSchemaIsolatesStatusAsAMapList(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	row := &problemsv1alpha1.Problem{
		ObjectMeta: metav1.ObjectMeta{Name: "zinc-pikachu-v1", Namespace: problemNamespace},
		Spec: problemsv1alpha1.ProblemSpec{
			Platform:  "nitroso",
			Service:   "zinc",
			Landscape: "pikachu",
			Version:   "v1",
		},
	}
	require.NoError(t, c.Create(ctx, row))
	t.Cleanup(func() { _ = c.Delete(ctx, row) })

	row.Status.ObservedGeneration = 9
	row.Status.Conditions = []metav1.Condition{problemCondition("Published")}
	require.NoError(t, c.Update(ctx, row))

	var afterSpecWrite problemsv1alpha1.Problem
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(row), &afterSpecWrite))
	require.Zero(t, afterSpecWrite.Status.ObservedGeneration)
	require.Empty(t, afterSpecWrite.Status.Conditions)

	afterSpecWrite.Status.ObservedGeneration = afterSpecWrite.Generation
	afterSpecWrite.Status.Conditions = []metav1.Condition{
		problemCondition("Published"),
		problemCondition("Stale"),
	}
	require.NoError(t, c.Status().Update(ctx, &afterSpecWrite))

	var afterStatusWrite problemsv1alpha1.Problem
	require.NoError(t, c.Get(ctx, client.ObjectKeyFromObject(row), &afterStatusWrite))
	require.Len(t, afterStatusWrite.Status.Conditions, 2)
	require.Equal(t, afterStatusWrite.Generation, afterStatusWrite.Status.ObservedGeneration)

	afterStatusWrite.Status.Conditions = []metav1.Condition{
		problemCondition("Published"),
		problemCondition("Published"),
	}
	err := c.Status().Update(ctx, &afterStatusWrite)
	require.True(t, apierrors.IsInvalid(err), "expected duplicate condition types to be rejected, got %v", err)
}

// TestProblemSchemaHasNoFleetGroupKind is the negative proof AT THE SERVER: the
// served surface carries no Problem in the fleet group, so the fleet compiler
// chart's Problem-under-apiVersions.fleet defect cannot be satisfied here.
func TestProblemSchemaHasNoFleetGroupKind(t *testing.T) {
	c := newProblemClient(t)
	ensureProblemNamespace(t, c)
	ctx := context.Background()

	forged := &unstructured.Unstructured{}
	forged.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "fleet.atomi.cloud",
		Version: "v1alpha1",
		Kind:    "Problem",
	})
	forged.SetName("zinc-raichu-v1")
	forged.SetNamespace(problemNamespace)
	require.NoError(t, unstructured.SetNestedField(forged.Object, "nitroso", "spec", "platform"))
	require.NoError(t, unstructured.SetNestedField(forged.Object, "zinc", "spec", "service"))
	require.NoError(t, unstructured.SetNestedField(forged.Object, "raichu", "spec", "landscape"))
	require.NoError(t, unstructured.SetNestedField(forged.Object, "v1", "spec", "version"))

	err := c.Create(ctx, forged)
	require.Error(t, err, "the served surface must have no fleet-group Problem")
	require.True(t,
		apimeta.IsNoMatchError(err) || apierrors.IsNotFound(err),
		"expected a no-kind-match or NotFound error, got %v", err)
}
