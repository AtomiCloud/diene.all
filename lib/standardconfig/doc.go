// Package standardconfig ships the Diene infrastructure configuration presets.
//
// The four presets — postgres, cache, kv, and storage — are the frozen infra
// blocks of C0 §3. Each is a KEYED MAP of named connections, so a service that
// needs a second Postgres pool or a second bucket adds YAML rather than code.
// Connection-pool names are UPPERCASE by contract (R14).
//
// This library ships PRESETS ONLY. It never loads, merges, or validates a
// configuration document: github.com/AtomiCloud/diene.go-config is the sole
// merger and validator. A service composes its own root schema from the engine
// blocks it uses (otel, auth-engine, api-engine), the infra presets it needs
// from here, and its own keys, and hands the composed schema to the config
// loader, which validates the fully merged tree exactly once. There is no
// one-call bootstrap here and there never will be — a preset that also wired
// itself up would have to know which merger it was talking to.
//
// Schemas are exported as plain draft-2020-12 JSON Schema fragments
// (map[string]any), the same shape the sibling engines export, so this package
// carries no dependency on the config library. Mount one with
// config.NewBlock(standardconfig.PostgresBlockKey, true, standardconfig.PostgresSchema()).
//
// The fragments deliberately do NOT constrain the SPELLING of a connection key:
// the config library matches keys canonically across snake, kebab, camel, and
// Pascal, and rejects patternProperties and propertyNames as authoring faults
// for exactly that reason. The key contract is therefore enforced in Go, and it
// has two halves that live on opposite sides of the loader. UPPERCASE (R14) is
// an AUTHORING convention, checked with [ValidKey] against names as written; it
// does not survive loading, because the loader canonicalizes key spelling. What
// does survive, and what [ValidateKeys] enforces on a decoded block, is that
// every connection name is an identifier — a name with a hyphen or a space has
// no reachable <PREFIX>BLOCK__NAME__KEY environment path, so its secret could
// never be injected. [Named] resolves a connection case-insensitively for the
// same reason: code asks for MAIN and the decoded block is keyed by main.
//
// Cache and kv share the Redis wire protocol and therefore share an entry
// shape, but they are SEPARATE presets under separate root keys because their
// durability semantics differ: cache is RAM-backed and ephemeral (Dragonfly),
// kv is persistent (Upstash in cloud landscapes, snapshot-durable Dragonfly
// locally). A cache instance may never be relabelled as kv.
//
// Secrets — the Postgres and Redis passwords and the storage credentials — are
// ordinary config keys left blank in YAML and injected per landscape through
// the environment override tier (R14, M33).
//
// Every non-nil error returned by this package carries a *problem.Error from
// github.com/AtomiCloud/diene.go-errors-problems, so callers recover structured
// RFC 9457 details with errors.As while errors.Is still reaches the cause.
//
// The companion github.com/AtomiCloud/diene.go-standard-config/testhelper
// package boots real containers for each preset and emits the matching,
// schema-valid keyed block, so a consumer's integration test is a start helper
// plus its own wiring.
package standardconfig
