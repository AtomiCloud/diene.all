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
printf 'package main\n\nimport (\n\t"context"\n\t"fmt"\n\n\t"%s/adapters/otelsdk"\n\t"%s/lib/otel"\n\t"%s/testhelper"\n)\n\nfunc main() {\n\tlogs := testhelper.NewInMemoryLoggerSink()\n\tmetrics := testhelper.NewInMemoryMetricsCollector()\n\ttraces := testhelper.NewInMemoryTraceEmitter()\n\truntime, err := otelsdk.New(\n\t\tcontext.Background(),\n\t\totel.DefaultConfig(),\n\t\ttesthelper.SampleIdentity(),\n\t\totelsdk.WithLoggerSink(logs),\n\t\totelsdk.WithMetricsCollector(metrics),\n\t\totelsdk.WithTraceEmitter(traces),\n\t)\n\tif err != nil { panic(err) }\n\tif err = runtime.LoggerSink().Emit(testhelper.SampleLogRecord()); err != nil { panic(err) }\n\tif err = runtime.MetricsCollector().Emit(testhelper.SampleMetricRecord()); err != nil { panic(err) }\n\tif err = runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil { panic(err) }\n\tif err = runtime.Shutdown(context.Background()); err != nil { panic(err) }\n\tfmt.Printf("%%d %%d %%d %%s\\n", len(logs.Records()), len(metrics.Records()), len(traces.Records()), runtime.ResourceAttributes()[otel.AttrServiceName])\n}\n' "${module}" "${module}" "${module}" >main.go
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go mod tidy
GOPROXY="${proxy}" GOSUMDB=sum.golang.org go build -o consumer .
[ "$(./consumer)" != "1 1 1 otel" ] && echo "❌ proxy consumer returned an unexpected result" >&2 && exit 1

echo "✅ Go proxy resolved ${module}@${tag} into a clean consumer"
