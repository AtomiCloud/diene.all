package clone_test

import (
	"reflect"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/clone"
)

type sample struct {
	Exported []string
	Nested   map[string]int
	hidden   string //nolint:unused // proves unexported fields are left zero, not copied
}

func TestValueClonesTypedContainers(t *testing.T) {
	t.Parallel()
	number := 7
	original := map[string]any{
		"anyMap":    map[string]any{"a": 1},
		"typedMap":  map[string]string{"k": "v"},
		"anySlice":  []any{1, "two", nil},
		"strSlice":  []string{"x", "y"},
		"array":     [2]int{1, 2},
		"pointer":   &number,
		"nilPtr":    (*int)(nil),
		"nilMap":    map[string]string(nil),
		"nilSlice":  []string(nil),
		"struct":    sample{Exported: []string{"a"}, Nested: map[string]int{"n": 1}, hidden: "secret"},
		"scalar":    "keep",
		"nilAnyKey": nil,
	}
	cloned := clone.Map(original)
	if !reflect.DeepEqual(cloned["anyMap"], original["anyMap"]) {
		t.Fatalf("anyMap not cloned equal: %v", cloned["anyMap"])
	}
	if _, ok := cloned["typedMap"].(map[string]string); !ok {
		t.Fatalf("typed map lost concrete type: %T", cloned["typedMap"])
	}
	if _, ok := cloned["strSlice"].([]string); !ok {
		t.Fatalf("typed slice lost concrete type: %T", cloned["strSlice"])
	}
	if _, ok := cloned["array"].([2]int); !ok {
		t.Fatalf("array lost concrete type: %T", cloned["array"])
	}
	clonedStruct, ok := cloned["struct"].(sample)
	if !ok || clonedStruct.hidden != "" {
		t.Fatalf("struct clone must keep exported fields and zero unexported: %+v", cloned["struct"])
	}
	if len(clonedStruct.Exported) != 1 || clonedStruct.Nested["n"] != 1 {
		t.Fatalf("struct exported fields not cloned: %+v", clonedStruct)
	}
}

func TestValueDeepIsolatesFromCallerMutation(t *testing.T) {
	t.Parallel()
	original := map[string]any{
		"typed": map[string]string{"k": "v"},
		"slice": []string{"a"},
		"nested": map[string]any{
			"inner": []any{map[string]any{"deep": 1}},
		},
	}
	cloned := clone.Map(original)

	original["typed"].(map[string]string)["k"] = "mutated"
	original["slice"] = append(original["slice"].([]string), "b")
	original["nested"].(map[string]any)["inner"].([]any)[0].(map[string]any)["deep"] = 99

	if cloned["typed"].(map[string]string)["k"] != "v" {
		t.Fatal("typed map mutation leaked into clone")
	}
	if len(cloned["slice"].([]string)) != 1 {
		t.Fatal("slice mutation leaked into clone")
	}
	if cloned["nested"].(map[string]any)["inner"].([]any)[0].(map[string]any)["deep"] != 1 {
		t.Fatal("deep nested mutation leaked into clone")
	}
}

func TestValueHandlesNilAndPointers(t *testing.T) {
	t.Parallel()
	if clone.Value(nil) != nil {
		t.Fatal("nil clones to nil")
	}
	number := 3
	pointer, ok := clone.Value(&number).(*int)
	if !ok || *pointer != 3 {
		t.Fatalf("pointer clone wrong: %v", clone.Value(&number))
	}
	*pointer = 4
	if number != 3 {
		t.Fatal("pointer clone must be independent")
	}
}

func TestMapNilClonesToNil(t *testing.T) {
	t.Parallel()
	if clone.Map(nil) != nil {
		t.Fatal("nil map clones to nil")
	}
}
