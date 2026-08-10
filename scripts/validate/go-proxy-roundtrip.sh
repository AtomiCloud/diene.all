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

# The clean consumer exercises the real published surface end to end — it takes
# the four frozen preset fragments, composes them into a root schema with the
# published config sibling, loads a three-layer document with a landscape
# overlay and an env-injected secret, and resolves a connection through the
# canonical keyed lookup — so the publish-time round trip doubles as the R-E12
# scratch-consumer proof for this module and, transitively, for the published
# diene.go-config and diene.go-errors-problems it composes with.
#
# NOTE: this heredoc is UNQUOTED so ${module} expands. Backticks would therefore
# be executed by the shell, so the YAML documents below are built with ordinary
# double-quoted Go string concatenation and carry no raw string literals.
cat >main.go <<CONSUMER
package main

import (
	"context"
	"fmt"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"${module}/lib/standardconfig"
	"${module}/testhelper"
)

func document(lines ...string) []byte {
	return []byte(strings.Join(lines, "\n") + "\n")
}

func main() {
	ctx := context.Background()

	// A service composes its own root schema: config's app block plus the infra
	// presets this module publishes. standard-config never merges or validates.
	schema := config.ComposeSchema(
		config.AppBlockSchema(),
		config.NewBlock(standardconfig.PostgresBlockKey, true, standardconfig.PostgresSchema()),
		config.NewBlock(standardconfig.CacheBlockKey, true, standardconfig.CacheSchema()),
		config.NewBlock(standardconfig.KvBlockKey, true, standardconfig.KvSchema()),
		config.NewBlock(standardconfig.StorageBlockKey, true, standardconfig.StorageSchema()),
	)

	base := document(
		"app:",
		"  landscape: lapras",
		"  platform: sulfoxide",
		"  service: billing",
		"  module: core",
		"  version: 1.0.0",
		"postgres:",
		"  MAIN:",
		"    host: postgres.invalid",
		"    port: 5432",
		"    database: billing",
		"    username: billing",
		"    password: \"\"",
		"    ssl: false",
		"    pool:",
		"      min: 0",
		"      max: 10",
		"cache:",
		"  MAIN:",
		"    host: cache.invalid",
		"    port: 6379",
		"    password: \"\"",
		"    db: 0",
		"    tls: false",
		"kv:",
		"  MAIN:",
		"    host: kv.invalid",
		"    port: 6379",
		"    password: \"\"",
		"    db: 0",
		"    tls: false",
		"storage:",
		"  ASSETS:",
		"    endpoint: http://storage.invalid",
		"    region: us-east-1",
		"    bucket: assets",
		"    accessKeyId: \"\"",
		"    secretAccessKey: \"\"",
		"    forcePathStyle: true",
	)
	overlay := document(
		"postgres:",
		"  MAIN:",
		"    host: primary.lapras.invalid",
		"    ssl: true",
	)

	loaded, err := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithSchema(schema),
		config.WithBaseSource(config.NewBytesYAMLSource("base", base)),
		config.WithOverlaySource("lapras", config.NewBytesYAMLSource("lapras", overlay)),
		config.WithEnvSource(config.NewMapEnvSource("env", map[string]string{
			"ATOMI_POSTGRES__MAIN__PASSWORD": "injected",
		})),
	).Load(ctx)
	if err != nil {
		panic(err)
	}

	var block standardconfig.PostgresBlock
	if err := loaded.Decode(standardconfig.PostgresBlockKey, &block); err != nil {
		panic(err)
	}
	problems, err := standardconfig.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		panic(err)
	}

	// The keyed lookup resolves the AUTHORED name off the canonicalized block.
	main, err := standardconfig.Named(problems, block, "MAIN")
	if err != nil {
		panic(err)
	}
	canonical := strings.Join(standardconfig.Keys(block), ",") == "main"

	// The landscape overlay flipped the posture, the env injected the blank
	// secret last, and the sparse overlay left the base defaults alone.
	overlayApplied := main.Host == "primary.lapras.invalid" && main.SSL
	secretInjected := main.Password == "injected"
	defaultsKept := main.Database == "billing" && main.Pool.Max == 10

	// The shipped testhelper resolves and emits a schema-shaped block.
	fake := testhelper.FakeStorage("")
	assets := testhelper.RequireEntry(discard{}, fake, testhelper.DefaultKey)
	helperUsable := assets.Bucket == "app" && assets.AccessKeyID == ""

	fmt.Println(canonical, overlayApplied, secretInjected, defaultsKept, helperUsable)
}

// discard satisfies the testhelper assertion interface outside a test binary.
type discard struct{}

func (discard) Helper() {}

func (discard) Fatalf(format string, args ...any) {
	panic(fmt.Sprintf(format, args...))
}
CONSUMER

GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "true true true true true" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
