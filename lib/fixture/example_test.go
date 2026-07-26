package fixture_test

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/fixture"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// exampleProblems builds the harness problem factory.
func exampleProblems() *e2e.Problems {
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}
	return problems
}

// exampleBundle is the R14 three-layer fixture the examples build on.
func exampleBundle() fixture.Bundle {
	bundle, err := fixture.NewBuilder(exampleProblems()).
		WithApp(config.AppBlock{
			Landscape: "garden", Platform: "sulfoxide", Service: "billing",
			Module: "core", Version: "1.0.0",
		}).
		WithBlock("postgres", map[string]any{"MAIN": map[string]any{
			"host": "postgres.invalid", "port": 5432, "database": "billing",
		}}).
		WithOverlay("garden", "postgres", map[string]any{"MAIN": map[string]any{
			"host": "primary.garden.invalid", "ssl": true,
		}}).
		WithSecret("postgres.MAIN.password", "injected").
		WithList("api.scopes", []string{"read", "write"}).
		Build()
	if err != nil {
		panic(err)
	}
	return bundle
}

func ExampleNewBuilder() {
	bundle := exampleBundle()
	fmt.Println(bundle.Landscapes())
	// Output: [garden]
}

func ExampleBundle_Merged() {
	merged := exampleBundle().Merged("garden")
	postgres, valid := merged["postgres"].(map[string]any)
	if !valid {
		panic("the merged document has no postgres block")
	}
	entry, valid := postgres["MAIN"].(map[string]any)
	if !valid {
		panic("the postgres block has no MAIN entry")
	}
	// The overlay wins, the base defaults survive, and the secret stays blank in
	// the document.
	fmt.Println(entry["host"], entry["ssl"], entry["database"], fmt.Sprintf("%q", entry["password"]))
	// Output: primary.garden.invalid true billing ""
}

func ExampleBundle_Environ() {
	environ := exampleBundle().Environ(fixture.DefaultEnvPrefix)
	keys := make([]string, 0, len(environ))
	for key := range environ {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		fmt.Println(key + "=" + environ[key])
	}
	// Output:
	// ATOMI_API__SCOPES__0=read
	// ATOMI_API__SCOPES__1=write
	// ATOMI_POSTGRES__MAIN__PASSWORD=injected
}

func ExampleEnvKey() {
	fmt.Println(fixture.EnvKey("ATOMI_", "postgres.MAIN.pool.max"))
	// Output: ATOMI_POSTGRES__MAIN__POOL__MAX
}

func ExampleBundle_Materialize() {
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	layout, err := exampleBundle().Materialize(context.Background(), filesystem, "/tmp/case", exampleProblems())
	if err != nil {
		panic(err)
	}
	fmt.Println(layout.BasePath)
	fmt.Println(layout.OverlayPaths["garden"])
	// Output:
	// /tmp/case/base.yaml
	// /tmp/case/garden.yaml
}

func ExampleBundle_Document() {
	document, err := exampleBundle().Document("garden")
	if err != nil {
		panic(err)
	}
	fmt.Print(string(document))
	// Output:
	// postgres:
	//     MAIN:
	//         host: primary.garden.invalid
	//         ssl: true
}

func ExampleDirectory() {
	fmt.Println(fixture.Directory("/tmp/fixtures", "Sign In Then Pay"))
	// Output: /tmp/fixtures/sign-in-then-pay
}

func ExampleInstant() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Now: time.Date(2026, time.July, 26, 8, 30, 0, 0, time.UTC),
	})
	instant, err := fixture.Instant(system)
	if err != nil {
		panic(err)
	}
	fmt.Println(instant)
	// Output: 2026-07-26T08:30:00.000Z
}

func ExampleDuration() {
	fmt.Println(fixture.Duration("PT30S"))
	_, err := fixture.Duration("30s")
	fmt.Println(err != nil)
	// Output:
	// PT30S <nil>
	// true
}

func ExampleZone() {
	fmt.Println(fixture.Zone("Asia/Singapore"))
	_, err := fixture.Zone("+08:00")
	fmt.Println(err != nil)
	// Output:
	// Asia/Singapore <nil>
	// true
}
