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

# The clean consumer exercises the real published surface end to end — validate a
# token minted by the fake IdP, resolve a per-resource token through the cache,
# and run the ownership guard — so the publish-time round trip doubles as the
# R-E12 scratch-consumer proof for this module and, transitively, for the
# published diene.go-core-utils and diene.go-errors-problems it consumes.
cat >main.go <<CONSUMER
package main

import (
	"context"
	"fmt"

	"${module}/lib/authengine"
	"${module}/testhelper"
)

func main() {
	ctx := context.Background()
	idp := testhelper.NewFakeIdP(testhelper.FakeIdPOptions{})

	validator, err := idp.Validator()
	if err != nil {
		panic(err)
	}
	token, err := idp.MintAccessToken(testhelper.TokenRequest{Subject: "user-1", Roles: []string{"admin"}})
	if err != nil {
		panic(err)
	}
	principal, err := validator.Validate(ctx, token)
	if err != nil {
		panic(err)
	}

	guard, err := idp.Guard()
	if err != nil {
		panic(err)
	}
	owner := "user-1"
	ownerAllowed := guard.Sub(principal, &owner) == nil
	attackerDenied := guard.Sub(principal, ptr("user-2")) != nil
	adminAllowed := guard.SubOrAny(principal, nil, authengine.ClaimRoles, "admin") == nil

	fmt.Println(principal.Subject, ownerAllowed, attackerDenied, adminAllowed)
}

func ptr(value string) *string { return &value }
CONSUMER

GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "user-1 true true true" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
