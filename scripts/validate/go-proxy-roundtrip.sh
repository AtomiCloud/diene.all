#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy="${GOPROXY_URL:-$(yq -r '.proxy' .config/go-lib.yaml)}"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null || true; rm -rf "${tmp}"' EXIT

./scripts/validate/go-publish-guard.sh "${tag}"
cd "${tmp}"
go mod init example.invalid/go-lib-consumer >/dev/null
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go get "${module}@${tag}"

# The clean consumer exercises the real published surface end to end: it resolves
# a Garden preview target out of an injected environment, builds an R14
# three-layer fixture and materializes it onto the real filesystem through the
# published Vfs binding, loads it back through the composed root schema, runs a
# two-step journey against a driver, and classifies a harness failure as an RFC
# 9457 problem. The publish-time round trip therefore doubles as the R-E12
# scratch-consumer proof for this module and, transitively, for the published
# diene.go-interfaces, diene.go-core-utils, diene.go-config,
# diene.go-errors-problems, diene.go-otel and diene.go-standard-config it
# composes with.
#
# NOTE: this heredoc is UNQUOTED so ${module} expands. Backticks would therefore
# be EXECUTED by the shell, so there are no raw string literals below and no
# struct tags in any payload; the config lib matches fields case-insensitively
# anyway.
cat >main.go <<CONSUMER
package main

import (
	"context"
	"fmt"
	"os"

	"${module}/adapters/filesystem"
	"${module}/lib/e2e"
	"${module}/lib/fixture"
	"${module}/lib/preview"
	"${module}/testhelper"
	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func main() {
	ctx := context.Background()

	problems, err := testhelper.SampleProblems()
	if err != nil {
		panic(err)
	}

	// A Garden preview target read out of an injected environment through the
	// published interfaces seam, with the otel exporter flipped to the C0
	// http/protobuf port.
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{
		Environment: map[string]string{
			preview.EnvPlatform:     "sulfoxide",
			preview.EnvService:      "billing",
			preview.EnvModule:       "core",
			preview.EnvVersion:      "1.0.0",
			preview.EnvBaseURL:      "https://billing.garden.invalid",
			preview.EnvOtlpEndpoint: "http://alloy.garden.invalid:4318",
			preview.EnvIssuer:       "https://logto.garden.invalid/oidc",
			preview.EnvAudience:     "https://billing.garden.invalid",
			preview.EnvJWKSURI:      "https://logto.garden.invalid/oidc/jwks",
		},
	})
	target, err := preview.Resolve(system, problems)
	if err != nil {
		panic(err)
	}
	traces := target.OtelConfig().Traces
	targetResolved := target.Landscape == preview.DefaultLandscape &&
		traces.Enabled &&
		traces.Exporter.Otlp.Protocol == otel.ProtocolHTTPProtobuf &&
		traces.Exporter.Otlp.Endpoint == "http://alloy.garden.invalid:4318"

	// An R14 three-layer fixture: full base defaults, a sparse landscape overlay,
	// a blank secret in the document, and the C0 indexed environment layer.
	bundle, err := fixture.NewBuilder(problems).
		WithApp(target.AppBlock()).
		WithOverlay(target.Landscape, config.AppKey, map[string]any{"version": "2.0.0"}).
		WithSecret("postgres.MAIN.password", "injected").
		WithList("api.scopes", []string{"read", "write"}).
		Build()
	if err != nil {
		panic(err)
	}
	environ := bundle.Environ(fixture.DefaultEnvPrefix)
	c0Encoded := environ["ATOMI_API__SCOPES__0"] == "read" &&
		environ["ATOMI_API__SCOPES__1"] == "write" &&
		environ["ATOMI_POSTGRES__MAIN__PASSWORD"] == "injected"

	// Materialized onto the REAL filesystem through the published binding, then
	// loaded back through the composed root schema the config lib validates.
	directory, err := os.MkdirTemp("", "diene-go-e2e-roundtrip-")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(directory)
	layout, err := bundle.Materialize(ctx, filesystem.NewVfs(), fixture.Directory(directory, "Round Trip"), problems)
	if err != nil {
		panic(err)
	}
	// Validated against just the app block: the round trip proves the three
	// layers land in the right order, not that a whole service document is
	// complete. preview.Schema() is asserted separately below, because a fixture
	// missing a REQUIRED engine block is a validation failure by design.
	loader, err := bundle.Loader(fixture.LoaderOptions{
		Layout:    layout,
		Landscape: target.Landscape,
		Schema:    config.ComposeSchema(config.AppBlockSchema()),
	})
	if err != nil {
		panic(err)
	}
	loaded, err := loader.Load(ctx)
	if err != nil {
		panic(err)
	}
	var app config.AppBlock
	if err := loaded.Decode(config.AppKey, &app); err != nil {
		panic(err)
	}
	composedRoot, composedOK := preview.Schema().Root()["properties"].(map[string]any)
	layersApplied := app.Service == "billing" && app.Version == "2.0.0" &&
		composedOK && len(composedRoot) == len(preview.EngineBlocks())

	// A two-step journey against a driver, with the report asserted by the
	// shipped TestHelper.
	driver, err := testhelper.NewEchoDriver(problems)
	if err != nil {
		panic(err)
	}
	journey := e2e.Journey{
		Name: "round-trip",
		Steps: []e2e.Step{
			{
				Name:       "echoes its arguments",
				Invocation: e2e.Invocation{Args: []string{"seed"}},
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"args: seed"}},
			},
			{
				Name:       "honours the requested exit code",
				Invocation: e2e.Invocation{Env: map[string]string{testhelper.ExitCodeVar: "3"}},
				Expect:     e2e.Expectation{ExitCode: 3, StderrContains: []string{"exit: 3"}},
			},
		},
	}
	report, err := e2e.RunJourney(ctx, driver, journey, problems)
	if err != nil {
		panic(err)
	}
	journeyRan := testhelper.CheckReport(report, journey) == nil && len(report.Steps) == 2

	// A harness failure classified as an RFC 9457 problem through the published
	// errors-problems sibling.
	_, emptyErr := e2e.RunJourney(ctx, driver, e2e.Journey{Name: "vacuous"}, problems)
	envelope, checkErr := testhelper.CheckHarnessProblem(emptyErr, e2e.ProblemJourneyEmpty)
	problemTyped := checkErr == nil && envelope.Status == 422

	fmt.Println(targetResolved, c0Encoded, layersApplied, journeyRan, problemTyped)
}
CONSUMER

GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "true true true true true" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
