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
cat >main.go <<EOF
package main

import (
	"context"
	"fmt"

	"${module}/lib/config"
)

func main() {
	loader := config.NewLoader(
		config.WithEnvPrefix("ATOMI_"),
		config.WithBaseSource(config.NewBytesYAMLSource("base", []byte("app:\n  landscape: proxy\n"))),
		config.WithEnvSource(config.NewMapEnvSource("env", map[string]string{"ATOMI_APP__VERSION": "9.9.9"})),
	)
	cfg, err := loader.Load(context.Background())
	if err != nil {
		panic(err)
	}
	app, _ := cfg.App()
	fmt.Printf("%s %s\n", app.Landscape, app.Version)
}
EOF
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "proxy 9.9.9" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
