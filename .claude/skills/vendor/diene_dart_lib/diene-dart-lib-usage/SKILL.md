---
name: diene-dart-lib-usage
description: Use when consuming package:diene_dart_lib — importing the barrel, calling the Note value type and summarizeNote transform, or deciding whether to reach for its dependency-light TestHelper.
---

# diene_dart_lib usage

Import only the public barrel; never reach into `lib/src`:

```dart
import 'package:diene_dart_lib/diene_dart_lib.dart';
```

## Public API

- `Note({required String title, required String body})` — an immutable value
  type with value equality. `Note.fromJson(Map<String, Object?>)` decodes the
  JSON wire form and throws `FormatException` on a missing/empty title or a
  non-string body; `toJson()` encodes it back.
- `summarizeNote(Note note, {int maxLength = defaultSummaryLength})` — a pure
  function returning a single-line summary. It collapses whitespace, joins the
  title and a non-empty body with an em dash, and truncates with an ellipsis
  beyond `maxLength`. It throws `ArgumentError` when `maxLength` is not positive.
- `defaultSummaryLength` — the default cap (`80`).

Prefer `Note.fromJson` / `toJson` only at a JSON wire boundary. Keep the value
type immutable; build a new `Note` rather than mutating.

## TestHelper decision

`package:diene_dart_lib/test_helper.dart` ships `assertNoteSummary`, a
dependency-light assertion that throws `NoteAssertionFailure` (a `StateError`)
on mismatch and imports no test framework. Use it in consumer tests when you
want a runner-agnostic assertion over the summary. If you only need one-off
checks, plain `package:test` matchers over `summarizeNote` are enough — reach
for the TestHelper when the assertion is shared across suites or runners.

See `patterns.md` for the TestHelper rationale and how a materialized child
replaces the sample domain.
