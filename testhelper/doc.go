// Package testhelper ships the container glue, deterministic block fakes, and
// fail-fast assertions that consumers of
// github.com/AtomiCloud/diene.go-standard-config would otherwise rebuild in
// every repository.
//
// The glue is the point. A preset schema alone does not help a consumer write
// an integration test: what costs an afternoon per repository is booting the
// right image with the right wait strategy and then hand-translating the mapped
// port into a config block that matches the preset. [StartPostgres],
// [StartCache], [StartKv], and [StartStorage] do both halves — they start a real
// container AND return the keyed, schema-valid block for it — so a consumer's
// integration test is a start helper plus its own wiring.
//
// Containers are reached through the [Runtime] seam rather than called
// directly, so the glue's failure paths are exercised deterministically with a
// stub while the real path runs against Docker.
//
// The fakes ([FakePostgres] and friends) are container-free blocks for unit
// tiers: deterministic values, blank secrets, UPPERCASE keys, valid against the
// same preset schemas the real glue emits.
//
// The assertions depend only on the minimal [TestingT] interface (which
// *testing.T satisfies), never on the concrete testing type, so they stay
// framework-free and are themselves black-box testable with a recording double.
package testhelper
