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
printf 'package main\n\nimport (\n\t"context"\n\t"fmt"\n\n\t"%s/lib/coreutils"\n\t"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"\n\t"github.com/AtomiCloud/diene.go-interfaces/testhelper"\n)\n\nfunc main() {\n\tfilesystem := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})\n\t_ = filesystem.WriteText(context.Background(), "/greeting.txt", "hello", interfaces.WriteOptions{CreateParents: true})\n\tdigest, _ := coreutils.HashFile(context.Background(), filesystem, "/greeting.txt")\n\tfmt.Println(coreutils.Slugify("Hello World"), digest[:8])\n}\n' "${module}" >main.go
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "hello-world 2cf24dba" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
