package authengine_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// sampleResources are two registered backends, which is the shape that matters: one
// backend can never prove per-backend independence.
func sampleResources() []authengine.Resource {
	return []authengine.Resource{
		{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid", Scopes: []string{"read:booking"}},
		{Name: "nitroso-tin", Indicator: "https://api.tin.invalid"},
	}
}

// newTree builds a resource tree over [sampleResources].
func newTree(t *testing.T) authengine.ResourceTree {
	t.Helper()

	tree, err := authengine.NewResourceTree(newProblems(t), sampleResources()...)
	requireNoError(t, err)
	return tree
}

func TestNewResourceTreeRequiresAProblemFactory(t *testing.T) {
	t.Parallel()

	if _, err := authengine.NewResourceTree(nil); err == nil {
		t.Fatal("expected a resource tree without a problem factory to be rejected")
	}
}

func TestNewResourceTreeRejectsUnusableDeclarations(t *testing.T) {
	t.Parallel()

	problems := newProblems(t)
	cases := []struct {
		name      string
		resources []authengine.Resource
	}{
		{
			name:      "blank name",
			resources: []authengine.Resource{{Name: "  ", Indicator: "https://api.invalid"}},
		},
		{
			name:      "blank indicator",
			resources: []authengine.Resource{{Name: "zinc", Indicator: " "}},
		},
		{
			name: "duplicate name",
			resources: []authengine.Resource{
				{Name: "zinc", Indicator: "https://one.invalid"},
				{Name: "zinc", Indicator: "https://two.invalid"},
			},
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			_, err := authengine.NewResourceTree(problems, testCase.resources...)
			requireProblem(t, err, authengine.ProblemConfigInvalid)
		})
	}
}

func TestResourceTreeKeepsDeclarationOrder(t *testing.T) {
	t.Parallel()

	tree := newTree(t)

	names := tree.Names()
	if len(names) != 2 || names[0] != "alcohol-zinc" || names[1] != "nitroso-tin" {
		t.Fatalf("expected declaration order, got %v", names)
	}
	if len(tree.Resources()) != 2 {
		t.Fatalf("expected two resources, got %d", len(tree.Resources()))
	}
}

func TestResourceTreeCopiesDeclaredScopes(t *testing.T) {
	t.Parallel()

	declared := sampleResources()
	tree, err := authengine.NewResourceTree(newProblems(t), declared...)
	requireNoError(t, err)

	declared[0].Scopes[0] = "mutated"
	resource, found := tree.Lookup("alcohol-zinc")
	if !found {
		t.Fatal("expected the declared resource to be present")
	}
	if resource.Scopes[0] != "read:booking" {
		t.Fatalf("expected the tree to own its scopes, got %v", resource.Scopes)
	}

	// The snapshot handed out must be independent too.
	snapshot := tree.Resources()
	snapshot[0].Name = "mutated"
	if names := tree.Names(); names[0] != "alcohol-zinc" {
		t.Fatalf("expected Resources to return a copy, got %v", names)
	}
}

func TestResourceTreeLookupReportsAnUnknownName(t *testing.T) {
	t.Parallel()

	if _, found := newTree(t).Lookup("absent"); found {
		t.Fatal("expected an undeclared resource to be absent")
	}
}

func TestResourceTreeRequireNamesWhatIsDeclared(t *testing.T) {
	t.Parallel()

	tree := newTree(t)

	resource, err := tree.Require("nitroso-tin")
	requireNoError(t, err)
	if resource.Indicator != "https://api.tin.invalid" {
		t.Fatalf("expected the declared indicator, got %q", resource.Indicator)
	}

	envelope := requireProblem(t, mustFail(tree, "absent"), authengine.ProblemResourceUnregistered)
	declared, ok := envelope.Data["declared"].([]string)
	if !ok || len(declared) != 2 {
		t.Fatalf("expected the failure to name the declared resources, got %v", envelope.Data)
	}
}

// mustFail returns the error from requiring an undeclared resource.
func mustFail(tree authengine.ResourceTree, name string) error {
	_, err := tree.Require(name)
	return err
}
