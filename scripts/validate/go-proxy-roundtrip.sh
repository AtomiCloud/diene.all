#!/usr/bin/env bash
set -euo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
module="$(yq -r '.module' .config/go-lib.yaml)"
proxy="${GOPROXY_URL:-$(yq -r '.proxy' .config/go-lib.yaml)}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

./scripts/validate/go-publish-guard.sh "${tag}"
cd "${tmp}"
go mod init example.invalid/go-lib-consumer >/dev/null
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go get "${module}@${tag}"

# The clean consumer exercises the real published surface end to end — it stands
# up a fake backend, resolves a client from the tree, and drives all THREE
# response cases — so the publish-time round trip doubles as the R-E12
# scratch-consumer proof for this module and, transitively, for the published
# diene.go-auth-engine and diene.go-errors-problems it consumes.
#
# NOTE: this heredoc is UNQUOTED so ${module} expands. Backticks would therefore
# be executed by the shell, so the payload struct carries NO json tags and
# relies on encoding/json's case-insensitive field matching instead.
cat >main.go <<CONSUMER
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"${module}/lib/apiengine"
	"${module}/lib/wire"
	"${module}/testhelper"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

type invoice struct {
	ID string
}

func main() {
	ctx := context.Background()

	backend := testhelper.NewFakeBackend(testhelper.FakeBackendOptions{
		Routes: map[string]testhelper.Route{
			"/ok": {Status: http.StatusOK, Body: invoice{ID: "i-1"}},
			"/problem": testhelper.Canned(testhelper.ProblemOptions{
				Type:   "https://docs.example.com/docs/prod/api/billing/core/v1/quota-exceeded",
				Title:  "Quota exceeded",
				Status: http.StatusTooManyRequests,
				Data:   map[string]any{"limit": 100},
			}),
			"/down": {Status: http.StatusServiceUnavailable, Body: "service unavailable"},
		},
	})
	defer backend.Close()

	tree, err := testhelper.NewFakeTree(testhelper.FakeTreeOptions{
		Backends: map[string]*testhelper.FakeBackend{"billing": backend},
		Tokens:   map[string]string{"billing": "token-billing"},
	})
	if err != nil {
		panic(err)
	}
	client, err := tree.Tree.Backend("billing")
	if err != nil {
		panic(err)
	}

	// Case 1 — 2xx decodes into T.
	got, err := apiengine.Execute[invoice](ctx, client, apiengine.Request{Path: "/ok"})
	if err != nil {
		panic(err)
	}
	success := got.ID == "i-1"

	// Case 2 — 4xx surfaces the BACKEND's own envelope, data extension intact.
	var carried *problem.Error
	_, err = apiengine.Execute[invoice](ctx, client, apiengine.Request{Path: "/problem"})
	problemCase := errors.As(err, &carried) &&
		carried.Problem.Status == http.StatusTooManyRequests &&
		carried.Problem.Data["limit"] == float64(100)

	// Case 3 — 5xx surfaces the engine's own transport problem.
	_, err = apiengine.Execute[invoice](ctx, client, apiengine.Request{Path: "/down"})
	transportCase := errors.As(err, &carried) &&
		carried.Problem.Status == http.StatusBadGateway

	// The per-backend token came from the auth-engine retriever seam.
	authorized := backend.Requests()[0].Authorization() == "Bearer token-billing"

	// C0 section 1 wire codecs round-trip.
	timeout, err := wire.ParseDuration("PT10S")
	if err != nil {
		panic(err)
	}
	wireCase := timeout.String() == "PT10S"

	fmt.Println(success, problemCase, transportCase, authorized, wireCase)
}
CONSUMER

GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "true true true true true" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
