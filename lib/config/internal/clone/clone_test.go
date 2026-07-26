package clone_test

import (
	"reflect"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/clone"
)

// box carries exported mutable reference fields, to prove they are deep-cloned
// (isolated from caller mutation) even when reached through a struct value.
type box struct {
	Items []string
	Meta  map[string]string
}

// node is a self-referential pointer graph, to prove cyclic pointers terminate
// and their topology is preserved.
type node struct {
	Next *node
	Val  int
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
	if got, ok := cloned["array"].([2]int); !ok || got != [2]int{1, 2} {
		t.Fatalf("array lost value or type: %v", cloned["array"])
	}
	if got, ok := cloned["nilPtr"].(*int); !ok || got != nil {
		t.Fatalf("nil pointer must stay nil: %v", cloned["nilPtr"])
	}
	if got, ok := cloned["nilMap"].(map[string]string); !ok || got != nil {
		t.Fatalf("nil typed map must stay a nil map of its type: %#v", cloned["nilMap"])
	}
	if got, ok := cloned["nilSlice"].([]string); !ok || got != nil {
		t.Fatalf("nil typed slice must stay a nil slice of its type: %#v", cloned["nilSlice"])
	}
	if cloned["scalar"] != "keep" || cloned["nilAnyKey"] != nil {
		t.Fatalf("scalar/nil leaf corrupted: %v %v", cloned["scalar"], cloned["nilAnyKey"])
	}
}

func TestValuePreservesStructPrivateState(t *testing.T) {
	t.Parallel()
	// time.Time has only unexported fields; the whole-value copy must preserve
	// them rather than rebuild a zeroed struct from settable fields.
	instant := time.Date(2026, 7, 25, 10, 30, 0, 0, time.UTC)
	cloned := clone.Map(map[string]any{"t": instant})
	got, ok := cloned["t"].(time.Time)
	if !ok || got.IsZero() || !got.Equal(instant) || got.Location() != time.UTC {
		t.Fatalf("time.Time private state corrupted: %v (zero=%v)", got, got.IsZero())
	}
}

func TestValueIsolatesExportedStructFields(t *testing.T) {
	t.Parallel()
	source := box{Items: []string{"a"}, Meta: map[string]string{"k": "v"}}
	cloned := clone.Map(map[string]any{"b": source})

	// Mutating the source struct's exported reference fields must not reach the
	// clone: each exported mutable field is deep-cloned.
	source.Items[0] = "mutated"
	source.Meta["k"] = "mutated"

	got, ok := cloned["b"].(box)
	if !ok {
		t.Fatalf("struct clone lost its type: %T", cloned["b"])
	}
	if got.Items[0] != "a" {
		t.Fatalf("exported slice field not isolated: %v", got.Items)
	}
	if got.Meta["k"] != "v" {
		t.Fatalf("exported map field not isolated: %v", got.Meta)
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

func TestValuePreservesSharedMapAlias(t *testing.T) {
	t.Parallel()
	shared := map[string]any{"x": 1}
	cloned := clone.Map(map[string]any{"a": shared, "b": shared})

	ca, aok := cloned["a"].(map[string]any)
	cb, bok := cloned["b"].(map[string]any)
	if !aok || !bok {
		t.Fatal("aliased maps must clone to maps")
	}
	ca["x"] = 2
	if cb["x"] != 2 {
		t.Fatal("shared map alias must clone to a single shared object")
	}
	if shared["x"] != 1 {
		t.Fatal("clone must be independent of the source alias")
	}
}

func TestValuePreservesSharedSliceAndPointerAliases(t *testing.T) {
	t.Parallel()
	slice := []any{1}
	number := 5
	cloned := clone.Map(map[string]any{"x": slice, "y": slice, "p": &number, "q": &number})

	cx, xok := cloned["x"].([]any)
	cy, yok := cloned["y"].([]any)
	if !xok || !yok {
		t.Fatal("aliased slices must clone to slices")
	}
	cx[0] = 99
	if cy[0] != 99 {
		t.Fatal("shared slice alias must clone to a single shared backing array")
	}
	if slice[0] != 1 {
		t.Fatal("slice clone must be independent of the source")
	}

	cp, pok := cloned["p"].(*int)
	cq, qok := cloned["q"].(*int)
	if !pok || !qok {
		t.Fatal("aliased pointers must clone to pointers")
	}
	if cp != cq {
		t.Fatal("shared pointer alias must clone to a single shared pointer")
	}
	*cp = 9
	if number != 5 {
		t.Fatal("pointer clone must be independent of the source")
	}
	if *cq != 9 {
		t.Fatal("shared pointer clones must observe each other")
	}
}

func TestValuePreservesSelfReferentialCycles(t *testing.T) {
	t.Parallel()
	cyclicMap := map[string]any{"v": 1}
	cyclicMap["self"] = cyclicMap
	clonedMap, ok := clone.Value(cyclicMap).(map[string]any)
	if !ok {
		t.Fatal("map clone lost its type")
	}
	clonedMap["v"] = 2
	if clonedMap["self"].(map[string]any)["v"] != 2 {
		t.Fatal("map self-cycle must be preserved as one shared object")
	}

	cyclicSlice := []any{nil}
	cyclicSlice[0] = cyclicSlice
	clonedSlice, ok := clone.Value(cyclicSlice).([]any)
	if !ok {
		t.Fatal("slice clone lost its type")
	}
	inner, ok := clonedSlice[0].([]any)
	if !ok || len(inner) != 1 {
		t.Fatalf("slice self-cycle topology lost: %v", clonedSlice)
	}
	clonedSlice[0] = "sentinel"
	if inner[0] != "sentinel" {
		t.Fatal("slice self-cycle must terminate and share one backing array")
	}

	first := &node{Val: 1}
	first.Next = first
	clonedNode, ok := clone.Value(first).(*node)
	if !ok || clonedNode.Val != 1 || clonedNode.Next != clonedNode {
		t.Fatalf("pointer self-cycle must be preserved: %+v", clonedNode)
	}
}

func TestValueClonesOverlappingSliceViewsDistinctly(t *testing.T) {
	t.Parallel()
	// Two views over one backing array share a first element but differ in length;
	// keying the memo only on pointer+type would return the wrong header, so the
	// short view must not clone to the long view's length.
	base := []int{1, 2, 3, 4}
	cloned := clone.Map(map[string]any{"short": base[0:2], "full": base[0:4]})

	cs, csok := cloned["short"].([]int)
	cf, cfok := cloned["full"].([]int)
	if !csok || !cfok || len(cs) != 2 || len(cf) != 4 {
		t.Fatalf("subslice views must clone to their own lengths: short=%v full=%v", cs, cf)
	}
	cs[0] = 99
	if cf[0] == 99 {
		t.Fatal("distinct-length views must clone to independent backing arrays")
	}
}

func TestValueClonesNonNilEmptySlice(t *testing.T) {
	t.Parallel()
	got, ok := clone.Value([]int{}).([]int)
	if !ok || got == nil || len(got) != 0 {
		t.Fatalf("non-nil empty slice must clone to a non-nil empty slice: %#v", got)
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
