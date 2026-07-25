---
name: diene-go-otel-usage
description: Use Diene's Go OpenTelemetry engine and its consumer-facing TestHelper package.
---

# Diene Go OpenTelemetry usage

Use `github.com/AtomiCloud/diene.go-otel` through its documented public APIs.
Start with the compiling examples and the package conventions in
`docs/developer/go-lib-baseline.md`.

For tests, import `<module>/testhelper` when it removes repeated consumer setup;
never add `export_test.go` or privileged white-box shims. New helper behavior
needs black-box meta tests and targeted meta coverage.

Before changing an exported API, run `./scripts/ci/pkg-validate.sh all`. Keep v1
changes backward compatible; an intentional breaking release needs a reviewed
`/v2` module-path migration.
