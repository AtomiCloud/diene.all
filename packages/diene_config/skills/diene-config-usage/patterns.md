# diene_config patterns

## Schema ownership

The rule that keeps this package small: **`diene_config` owns mechanics, never
schemas.**

```dart
// In auth_engine, beside the code that READS these settings:
final ConfigBlock<AuthSettings> authBlock = ConfigBlock<AuthSettings>(
  key: 'auth',
  decode: (Map<String, Object?> values) => AuthSettings(
    issuer: Uri.parse(values['issuer']! as String),
    scopes: (values['scopes']! as List<Object?>).cast<String>(),
  ),
);

// In the application, composing what the engines exported plus its own:
final ConfigSchema schema = ConfigSchema(
  blocks: <ConfigBlockSchema>[authBlock, apiBlock, myOwnFeatureBlock],
);
```

Consequences worth stating:

- An engine changes its settings by editing its own block. The app recompiles;
  `diene_config` does not change.
- Two blocks whose keys canonicalise together (`app-settings` and
  `appSettings`) are ambiguous and throw at construction — a `ConfigSchema` is
  source code, so this is a compile-adjacent error, not a runtime condition.
- Retain the exact block objects passed to `ConfigSchema` and reuse them for
  typed slice access. Membership is by instance identity; a newly constructed
  same-key lookalike is not composed and cannot read the original block's
  decoded value.
- An unknown root key is rejected by default, because a misspelled setting that
  is silently ignored is how a typo reaches production. Pass
  `rejectUnknownBlocks: false` only when a foreign tool genuinely shares the
  document.

## Rejecting input from a decoder

A decoder throws to reject; the schema catches every throw and folds them into
one `schema_invalid` problem whose `data.errors` lists them all.

```dart
decode: (Map<String, Object?> values) {
  final Object? retries = values['retries'];
  if (retries is! int || retries < 0) {
    throw FormatException('retries must be a non-negative int, got $retries');
  }
  return Settings(retries: retries);
}
```

Throwing here — rather than returning a `Result` — is deliberate: a block is a
plain callback written by whoever owns the settings, and requiring a `Result`
return would force every engine to depend on `diene_result` merely to describe
its own configuration. The throw never escapes to the caller.

## Telling a config failure from a foreign one

The loader propagates the `diene_core_utils` coercion envelope **unchanged**
when a define key is malformed, so its precise vocabulary survives. Branch on
provenance rather than on a raw string:

```dart
configProblemCode(problem).match(
  some: (ConfigProblemCode code) => switch (code) {
    ConfigProblemCode.sourceUnreadable => retryWithBundledDefaults(),
    ConfigProblemCode.schemaInvalid => reportToDeveloper(problem),
    _ => abortStartup(problem),
  },
  none: () => abortStartup(problem),  // minted elsewhere, e.g. coercion
);
```

## The TestHelper pattern

`lib/test_helper.dart` is a **dependency-light** sub-library: it imports the
public barrel and the family's hosted packages, and nothing else — no
`package:test`, `matcher`, `mockito`, or `mocktail`. It ships inside the
published archive, so a test-framework import there would land in the runtime
graph of every consumer that merely depends on `diene_config`.

Rules for a helper in this family:

- Assert over the **public barrel** only; never import `lib/src` internals.
- Throw a plain error type — here `ConfigAssertionFailure`, a `StateError` — so
  any runner reports it.
- Build fixtures through the **real** production path. `ConfigStubBuilder` runs
  `ConfigSchema.validate`, and `FakeConfigHarness` drives the real
  `ConfigLoader`, precisely so a fake cannot drift from what ships.
- Dogfood every assertion with a **meta test** proving it accepts a known-good
  case AND rejects a known-bad one. An assertion only exercised on the happy
  path is an assertion that might never fail.

Meta coverage is a separate ledger scoped to `lib/test_helper.dart`; the unit
ledger covers `lib/src/**`. Keep the two surfaces disjoint.

## Fake-versus-real parity

For a package whose whole job is layering, the fakes must agree with real YAML
on the **whole** matrix, not just the happy path. `test/meta/` runs both ways
and compares both channels — merged tree and typed slice on success, problem
code and error list on failure — across: base only; base+overlay;
base+overlay+dev; the full ladder with indexed defines; a blank define; an
invalid final schema; a malformed define key; an unknown root key; and nested
merging.

Comparing only "both failed" would let two different failures read as
agreement, so the comparator asserts the codes and details too — and is itself
shown to reject a deliberate divergence.

## Migrating an in-app AppConfig

`package:diene_config/config/app_config.dart` exists so an app carrying its own
`lib/config/app_config.dart` can swap one import instead of every call site. It
re-exports the whole surface and adds a one-shot `AppConfig` holder.

Treat it as scaffolding. Ambient global state is what the rest of the package
avoids, and the holder is deliberately strict about it: reading before
`install` throws instead of returning a silent default, and a second `install`
without `force` throws instead of letting two parts of the app disagree about
what the configuration is. Move call sites to threading `DieneConfig` through
constructors; the migration is done when nothing imports that entrypoint.

## C0 conformance in a downstream package

A downstream package proving its own §3 behaviour drives it from the same
pinned release rather than restating the id:

```dart
import 'package:diene_config/c0_config.dart';

expect(fixture['releaseId'], c0ConfigContract.provenance.releaseId);
```

Never hand-write a §3 vector. Project it from `contracts/c0/cases/config.json`
and let the `--check` gate catch drift.
