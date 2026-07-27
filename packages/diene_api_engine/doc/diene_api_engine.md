# diene_api_engine

`diene_api_engine` is the generic, pure-Dart **library template** for the Diene
family. It carries a small, deliberately replaceable sample domain plus the
template machinery (strict analysis, targeted coverage, a dependency-light
TestHelper, a C0 fixture harness, package hygiene, and a shipped usage skill). A
materialized child retokenizes the identity and replaces `lib/src/**` with its
own domain.

## Public surface

Import only the barrel:

```dart
import 'package:diene_api_engine/diene_api_engine.dart';
```

It exports:

- `Note` — an immutable value type with `title` and `body`, value equality, and
  a JSON wire codec (`Note.fromJson` / `toJson`). `fromJson` throws a
  `FormatException` when `title` is missing/empty or `body` is not a string.
- `summarizeNote(Note note, {int maxLength = defaultSummaryLength})` — a pure
  transform that renders a single-line summary, collapsing whitespace and
  truncating with an ellipsis beyond `maxLength`. Throws `ArgumentError` when
  `maxLength` is not positive.
- `defaultSummaryLength` — the default summary cap (`80`).

## Wire codec

The `Note` wire form is a plain JSON object:

```json
{ "title": "Release", "body": "Ship the template." }
```

`test/fixtures/c0/` pins a set of wire fixtures with a `manifest.json` mapping
each file to its SHA-256 digest. The conformance harness recomputes each digest,
asserts it matches, then decode→encode→decodes each fixture through the codec. A
corrupted fixture or a broken codec reddens the harness. The fixtures are
locally derived regression inputs, explicitly not authoritative C0 fixtures.

## TestHelper and meta testing

Consumer tests may import the dependency-light helper:

```dart
import 'package:diene_api_engine/test_helper.dart';
```

`assertNoteSummary(note, expected, {maxLength})` throws `NoteAssertionFailure`
(a `StateError`) on mismatch and imports no test framework, so it works with any
runner. The meta suite dogfoods the helper: it is shown accepting a known-good
summary and rejecting a known-bad one. Meta coverage is a separate ledger scoped
only to `lib/test_helper.dart`; the unit ledger covers `lib/src/**`.

## Replacing the sample

A real library deletes `lib/src/note.dart` and `lib/src/note_summary.dart`,
adds its own types under `lib/src/`, re-points the `export` lines in
`lib/diene_api_engine.dart`, and updates the TestHelper, tests, fixtures, example,
and this document. The surrounding template — analysis, coverage ledgers,
package validation, release, and publish machinery — is unchanged.
