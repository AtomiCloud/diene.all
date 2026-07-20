---
name: diene-go-lib-usage
description: Use the diene Go library template, its note API, and TestHelper package.
---

# Diene Go library usage

Use public packages through their documented APIs and preserve `(T, error)` Go
idioms. Start with the compiling examples in `lib/note/example_test.go` and the
package conventions in `docs/developer/go-lib-baseline.md`.

For tests, import `<module>/testhelper` when it removes repeated consumer setup;
never add `export_test.go` or privileged white-box shims. New helper behavior
needs black-box meta tests and targeted meta coverage.

Before changing an exported API, run `./scripts/ci/pkg-validate.sh all`. Keep v1
changes backward compatible; an intentional breaking release needs a reviewed
`/v2` module-path migration.
