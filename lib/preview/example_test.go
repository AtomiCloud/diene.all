package preview_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// exampleEnvironment is what a SIT job exports before the suite starts. In a real
// run these come from the deployment pipeline, and the harness reads them through
// the otel sibling's process-backed System seam.
func exampleEnvironment() map[string]string {
	return map[string]string{
		preview.EnvPlatform:     "sulfoxide",
		preview.EnvService:      "billing",
		preview.EnvModule:       "core",
		preview.EnvVersion:      "1.4.2",
		preview.EnvBaseURL:      "https://billing.garden.atomi.cloud",
		preview.EnvOtlpEndpoint: "http://alloy.garden.atomi.cloud:4318",
		preview.EnvIssuer:       "https://logto.garden.atomi.cloud/oidc",
		preview.EnvAudience:     "https://billing.garden.atomi.cloud",
		preview.EnvJWKSURI:      "https://logto.garden.atomi.cloud/oidc/jwks",
	}
}

// exampleProblems builds the harness problem factory.
func exampleProblems() *e2e.Problems {
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}
	return problems
}

func ExampleResolve() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Environment: exampleEnvironment(),
	})
	target, err := preview.Resolve(system, exampleProblems())
	if err != nil {
		panic(err)
	}
	fmt.Println(target.Landscape, target.Service, target.Resource)
	// Output: garden billing primary
}

func ExampleResolve_incomplete() {
	environment := exampleEnvironment()
	delete(environment, preview.EnvBaseURL)
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{Environment: environment})
	_, err := preview.Resolve(system, exampleProblems())
	fmt.Println(err != nil)
	// Output: true
}

func ExampleTarget_OtelConfig() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Environment: exampleEnvironment(),
	})
	target, err := preview.Resolve(system, exampleProblems())
	if err != nil {
		panic(err)
	}
	// SIT is the tier that turns the exporter on, against a collector that exists.
	traces := target.OtelConfig().Traces
	fmt.Println(traces.Enabled, traces.Exporter.Otlp.Protocol, traces.Exporter.Otlp.Endpoint)
	// Output: true http/protobuf http://alloy.garden.atomi.cloud:4318
}

func ExampleTarget_Identity() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Environment: exampleEnvironment(),
	})
	target, err := preview.Resolve(system, exampleProblems())
	if err != nil {
		panic(err)
	}
	identity := target.Identity()
	fmt.Println(identity.Platform, identity.Service, identity.Version)
	// Output: sulfoxide billing 1.4.2
}

func ExampleTarget_APIConfig() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Environment: exampleEnvironment(),
	})
	target, err := preview.Resolve(system, exampleProblems())
	if err != nil {
		panic(err)
	}
	backend := target.APIConfig().Backends[target.Resource]
	fmt.Println(len(target.APIConfig().Backends), backend.BaseURL)
	// Output: 1 https://billing.garden.atomi.cloud
}

func ExampleTarget_AuthConfig() {
	system := interfacesth.NewInMemorySystem(interfacesth.InMemorySystemOptions{
		Environment: exampleEnvironment(),
	})
	target, err := preview.Resolve(system, exampleProblems())
	if err != nil {
		panic(err)
	}
	fmt.Println(target.AuthConfig().IDP.Issuer)
	// Output: https://logto.garden.atomi.cloud/oidc
}

func ExampleEngineBlocks() {
	for _, block := range preview.EngineBlocks() {
		fmt.Println(block.Key, block.Required)
	}
	// Output:
	// app true
	// otel true
	// auth true
	// postgres false
	// cache false
	// kv false
	// storage false
}

func ExampleSchema() {
	root := preview.Schema().Root()
	properties, valid := root["properties"].(map[string]any)
	if !valid {
		panic("the composed schema has no properties")
	}
	fmt.Println(len(properties))
	// Output: 7
}

func ExampleAPIBlock() {
	// Exported on its own because composing it is currently fatal at
	// schema-compile time — see the package documentation.
	fmt.Println(preview.APIBlock().Key)
	// Output: api
}
