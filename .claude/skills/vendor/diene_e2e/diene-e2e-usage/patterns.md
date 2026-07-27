# diene_dart_lib patterns

## The TestHelper pattern

`lib/test_helper.dart` is a **dependency-light** sub-library: it imports the
public barrel and nothing else — no `package:test`, `matcher`, `mockito`, or
`mocktail`. Assertions throw `NoteAssertionFailure` (a `StateError`) on
mismatch, so the helper works under any test runner or plain `dart run`.

Ship a TestHelper when consumers repeatedly need the same assertion over your
public surface. Keep these rules:

- Assert over the **public barrel** only; never import `lib/src` internals.
- Throw a plain error type (extend `StateError`/`ArgumentError` or implement
  `Exception`); do not add a test framework to the runtime graph.
- Dogfood it with a **meta test** (`test/meta/`) that proves it both accepts a
  known-good case and rejects a known-bad case (expects a throw).
- Meta coverage is a separate ledger scoped only to `lib/test_helper.dart`; the
  unit ledger covers `lib/src/**`. Keep the two surfaces disjoint.

The meta tier is conditional: it activates only when a helper and a meta test
are added **together**. A package that needs no shared assertions can delete
`lib/test_helper.dart` and `test/meta/`, and the meta tier becomes a successful
no-op emitting no `meta` coverage flag.

## Replacing the sample domain

The `Note` type and `summarizeNote` transform are a generic placeholder. To
materialize a real library:

1. Delete `lib/src/note.dart` and `lib/src/note_summary.dart`; add your own
   types under `lib/src/`.
2. Re-point the `export` lines in `lib/diene_dart_lib.dart` to your files.
3. Rewrite `lib/test_helper.dart` (or delete it) to assert over your surface.
4. Replace `test/unit/**`, `test/meta/**`, and the `test/fixtures/c0/**`
   fixtures + `manifest.json` (recompute the SHA-256 digests).
5. Update `example/diene_dart_lib_example.dart`, `doc/diene_dart_lib.md`,
   `README.md`, and this skill's identity (`diene-dart-<name>-usage`).

Retokenize the package identity to `diene_<name>` and the mirror to
`AtomiCloud/diene.dart_<name>`. The surrounding template — strict analysis,
coverage ledgers, dead-code views, pana, and the OIDC publish flow — needs no
change.
