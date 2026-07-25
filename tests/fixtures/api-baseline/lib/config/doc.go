// Package config loads, merges, validates, and decodes Diene service
// configuration.
//
// The loader layers three sources in a fixed precedence: a base YAML document
// carrying full defaults, a sparse per-landscape YAML overlay, and the process
// environment applied LAST. The YAML layers are read with two independent
// [github.com/spf13/viper] instances combined through MergeConfigMap; the
// environment layer is produced by
// [github.com/AtomiCloud/diene.go-core-utils/lib/coreutils.EnvironmentToNestedMap]
// so lists arrive as contiguous indexed keys (FOO__0, FOO__1) rather than a
// JSON or comma-separated encoding, and it is folded on with
// [github.com/AtomiCloud/diene.go-core-utils/lib/coreutils.DeepMerge].
//
// Validation happens exactly once, against the fully merged tree, using a
// generated JSON Schema (draft 2020-12). A service composes the root schema
// from engine-owned [Block] fragments plus its own keys: config never defines
// the otel, auth-engine, or api-engine block schemas, it only merges and
// validates them. A validation failure is reported as a problem-typed error
// (github.com/AtomiCloud/diene.go-errors-problems), recoverable with the
// validation-error catalog id and HTTP 400, and carries the offending field
// paths and messages as readable issue data.
//
// The environment prefix is a required per-application option with no baked
// default; ATOMI_ is only an example. Configuration keys match across snake,
// kebab, camel, and Pascal spellings, blank environment values are treated as
// unset, and every committed configuration YAML declares its schema on its
// first line.
package config
