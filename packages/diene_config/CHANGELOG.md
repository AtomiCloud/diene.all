# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## 1.0.0

- Add the layered loader: full base YAML → sparse flavor/landscape overlay →
  optional development hook → enumerated `--dart-define` values last, with the
  service-composed schema validating the FINAL merged tree exactly once. No
  intermediate layer is validated or exposed, so a base that is incomplete on
  its own is correct when a later layer completes it.
- Add `YamlConfigSource`, which reads a layer through an injected text callback
  and converts the parsed document into plain collections. The package imports
  neither `dart:io` nor Flutter, so it runs on the VM, on the web, and in
  Flutter; a Flutter caller passes `rootBundle.loadString` and a pure Dart
  caller `File(path).readAsString`.
- Add service-composed schemas: `ConfigBlock<T>` decoders exported by the
  engines that read them, `ConfigBlockSchema` for type-erased composition, and
  `ConfigSchema` for root validation. This package owns composition mechanics
  and never defines another library's block.
- Add the immutable `DieneConfig` with typed `slice`, `hasSlice` /
  `optionalSlice` for optional blocks, untyped `rawSlice`, a deeply
  unmodifiable `raw` tree, and `stableProjection` for deterministic hashing.
- Add the `landscape()` accessor over the build-time `DIENE_LANDSCAPE` define,
  with `DartDefineLandscapeSource`. The store track IS the landscape: there is
  no hostname sniffing, runtime lookup, or remote detection, and a blank define
  is ABSENT rather than the empty landscape.
- Report every expected failure as a `Result` value carrying the canonical RFC
  9457 `Problem` from `diene_problems`, with the `type` URI minted only by the
  single C0 §2 builder: `ConfigProblemCode`, `configProblem`, `configFailure`,
  and `configProblemCode` for reading a code back. `schema_invalid` collects
  every problem in one pass. Throwing is reserved for programmer misuse.
- Propagate the `diene_core_utils` coercion envelope UNCHANGED when a
  `--dart-define` key is malformed, so its precise vocabulary survives instead
  of being re-minted under a vaguer config code.
- Consume the hosted `diene_core_utils` C0 §3 primitives (`deepMergeAll`,
  `canonicalConfigKey`, `environmentToNestedMap`, `stableConfig`) rather than
  shipping a private merge or environment-key engine. Indexed list overrides use
  contiguous `FOO__0`, `FOO__1`, … keys only; JSON and comma encodings are never
  decoded; blank values are unset; key matching ignores case, hyphens, and
  underscores on both prefix and path, with the base layer's spelling winning.
- Export the pinned C0 §3 contract as the `c0_config.dart` sub-library, and
  drive conformance from a generated, digest-ledgered projection of the frozen
  `c0-fixtures-r2` release rather than hand-written vectors. All FIVE §3 vectors
  are bound, including the `finalLayerValidation` case `diene_core_utils`
  leaves to its consumer.
- Add the dependency-light `test_helper.dart` sub-library: `FakeConfigSource`,
  `FailingConfigSource`, `FakeLandscapeSource`, `ConfigStubBuilder`,
  `FakeConfigHarness`, and the `expectOkConfig` / `expectErrConfig` /
  `assertConfigProblem` / `assertConfigSlice` assertions. It imports no test
  framework, builds stubs through the real schema path, and drives the real
  loader, so a fake cannot drift from what ships. The meta suite proves every
  assertion on both a known-good and a known-bad case, and runs the whole layer
  matrix through fakes and real YAML to prove parity on both channels.
- Add the `config/app_config.dart` compatibility entrypoint so an application
  migrating off an in-app `AppConfig` swaps one import rather than every call
  site. It is documented as a migration aid: reading before install throws
  rather than defaulting, and a second install requires an explicit `force`.
