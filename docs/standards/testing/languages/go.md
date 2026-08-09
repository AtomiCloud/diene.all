# Testing in Go

All tests are strict black-box tests: every `*_test.go` file uses
`package <name>_test`, and `export_test.go` is forbidden. Unit tests live under
`tests/unit/` and cover only `lib/**`; integration tests live under `tests/int/`
and prove adapters against real dependencies with testcontainers-go. Use
`-coverpkg` include scopes rather than exclusion lists.
