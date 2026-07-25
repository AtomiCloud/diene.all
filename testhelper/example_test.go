package testhelper_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-config/testhelper"
)

// ExampleRequireConfig shows the consumer pattern: drive the real loader over
// in-memory fakes and assert a successful load in one call.
func ExampleRequireConfig() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(testhelper.BaseSource(testhelper.BaseDocument())),
		config.WithEnvSource(testhelper.EnvSource(nil)),
		config.WithSchema(testhelper.Schema()),
	)
	cfg, err := loader.Load(context.Background())

	// A *testing.T satisfies TestingT; this example uses a no-op stand-in.
	cfg = testhelper.RequireConfig(noopT{}, cfg, err)
	app, _ := cfg.App()
	fmt.Println(app.Service)
	// Output: config
}

// noopT is a stand-in TestingT for the runnable example.
type noopT struct{}

func (noopT) Helper()               {}
func (noopT) Fatalf(string, ...any) {}
