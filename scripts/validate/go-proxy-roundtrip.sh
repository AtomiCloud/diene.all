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
printf 'package main\n\nimport (\n\t"context"\n\t"fmt"\n\n\t"%s/lib/interfaces"\n\t"%s/testhelper"\n)\n\nfunc main() {\n\tterminal := testhelper.NewInMemoryTerminal()\n\tterminal.EnqueueResult(interfaces.TerminalOutput{Stdout: "ok"}, nil)\n\toutput, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand("echo", nil, nil, nil, true, false))\n\tfmt.Println(output.Stdout, err == nil)\n}\n' "${module}" "${module}" >main.go
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "ok true" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
