// Package problem implements the AtomiCloud RFC 9457 problem-details contract
// (C0 §2/§14) in Go idiom.
//
// Unlike the TypeScript/Dart/C# siblings, the Go family has NO result monad:
// fallible APIs return the idiomatic (T, error) pair and carry problem metadata
// on a concrete [Error] that is compatible with errors.Is/errors.As and
// %w wrapping. Consumers recover the [Problem] with
// `var pe *problem.Error; errors.As(err, &pe)`.
//
// The RFC 9457 `type` URI is minted in exactly ONE place — [TypeURI] —
// from an [ErrorPortal] service-tree block, with the `{version}` segment kept
// (D8). Every envelope, registry entry, catalog row, and local error resolves
// its `type` through that single builder, which is the duplication this package
// exists to prevent.
//
// The public surface mirrors the accepted Dart sibling 1:1 where Go allows:
//   - [Problem] — the RFC 9457 envelope plus the `data` and `recoverable`
//     extensions, with lossless JSON round-tripping.
//   - [ErrorPortal] / [TypeURI] / [InvalidSegmentError] — the
//     single-source type-URI builder and its boundary validation.
//   - [Type] / [Registry] and the [GenericProblems] baseline set.
//   - [CatalogEntry] / [CatalogEndpoint] / [Catalog] — the catalog
//     export producing per-row Problem CR content (C0 §14).
//   - [Error] and [FromObject] — the problem-typed error and the
//     total value→Problem transformer.
//   - [LocalError] / [ErrorSink] — unexpected-error wrapping into a
//     `local-error` Problem carrying the message and stack in `data`.
package problem
