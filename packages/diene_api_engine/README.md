# diene_api_engine

[![pub package](https://img.shields.io/pub/v/diene_api_engine.svg)](https://pub.dev/packages/diene_api_engine)
[![CI](https://github.com/AtomiCloud/diene.dart_api_engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.dart_api_engine/actions/workflows/ci.yaml)
[![unit coverage](https://codecov.io/gh/AtomiCloud/diene.dart_api_engine/graph/badge.svg?flag=unit)](https://codecov.io/gh/AtomiCloud/diene.dart_api_engine)
[![meta coverage](https://codecov.io/gh/AtomiCloud/diene.dart_api_engine/graph/badge.svg?flag=meta)](https://codecov.io/gh/AtomiCloud/diene.dart_api_engine)

The generic, pure-Dart **library template** for the Diene family. It ships a
small, replaceable sample domain — a `Note` value type with a JSON wire codec
and a pure summariser — inside the reusable template machinery (strict analysis,
targeted coverage, a dependency-light TestHelper, a C0 fixture harness, package
hygiene, and a shipped usage skill).

```dart
import 'package:diene_api_engine/diene_api_engine.dart';

const Note note = Note(title: 'Release', body: 'Ship the template.');

final String summary = summarizeNote(note);        // 'Release — Ship the template.'
final Note decoded = Note.fromJson(note.toJson());  // round-trips through JSON
```

## Public surface

- `Note` — immutable `title`/`body` value type with value equality and a JSON
  wire codec (`Note.fromJson` / `toJson`).
- `summarizeNote(note, {maxLength})` — a pure single-line summariser.
- `defaultSummaryLength` — the default summary cap.

## TestHelper

Consumer tests may import `package:diene_api_engine/test_helper.dart` for
`assertNoteSummary`, a dependency-light assertion that throws
`NoteAssertionFailure` on mismatch and pulls in no test framework.

Read the [package doc](doc/diene_api_engine.md) for the full API, wire contract,
C0 harness, and guidance on replacing the sample.

## Using this template

This is a template: a materialized child retokenizes the package identity to
`diene_<name>` / `AtomiCloud/diene.dart_<name>`, replaces `lib/src/**` with its
own domain, and re-points the barrel exports. See
`skills/diene-api-engine-usage/patterns.md`.

## Development

- `pls setup` resolves the workspace dependencies.
- `pls test` runs the unit, C0 conformance, and TestHelper meta suites.
- `pls test:coverage` enforces the separate unit and meta ledgers.
- `pls deadcode` runs the repository and production-only dead-code passes.
- `pls package:validate` runs the release guard, publish dry-run, and pana.
