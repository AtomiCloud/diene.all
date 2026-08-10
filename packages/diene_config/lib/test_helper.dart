/// Dependency-light fakes, builders, and assertions for `diene_config`
/// consumers.
///
/// This sub-library ships INSIDE the published package, so it imports no test
/// framework — no `package:test`, `matcher`, `mockito`, or `mocktail`. A failed
/// assertion throws [ConfigAssertionFailure] (a [StateError]), which every
/// runner reports as a failure, and which plain `dart run` reports too.
///
/// What it gives a consumer:
///
/// - [FakeConfigSource] / [FailingConfigSource] — in-memory layers, including
///   one that fails on purpose, so the error path is testable without a
///   filesystem;
/// - [FakeLandscapeSource] — a deterministic landscape;
/// - [ConfigStubBuilder] — a valid [DieneConfig] built through the REAL schema
///   path, so a stub cannot be shaped like something the loader would reject;
/// - [FakeConfigHarness] — the full four-layer ladder over in-memory sources;
/// - [expectOkConfig] / [expectErrConfig] / [assertConfigProblem] — assertions
///   over the `Result` channel that report the other channel's contents when
///   they fail, instead of a bare "expected Ok".
library;

import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'diene_config.dart';

/// Thrown when a dependency-light `diene_config` assertion fails.
///
/// Extends [StateError] so a consumer can catch it either as a [StateError] or
/// by its concrete type.
final class ConfigAssertionFailure extends StateError {
  /// Creates an assertion failure with a consumer-facing diagnostic.
  ConfigAssertionFailure(super.message);
}

/// An in-memory configuration layer with an observable load count.
///
/// [loadCount] exists so a test can prove the loader reads each layer exactly
/// once — a loader that re-read a layer per lookup would still produce the
/// right values and would still pass every value assertion.
final class FakeConfigSource implements ConfigSource {
  /// Creates a fake layer contributing [values].
  FakeConfigSource(Map<String, Object?> values)
    : _values = deepClone(values)! as JsonObject;

  final JsonObject _values;

  /// How many times [load] has been called.
  int loadCount = 0;

  @override
  Future<Result<JsonObject>> load() async {
    loadCount += 1;
    // A fresh clone per load: a caller that mutates one result must not be
    // able to corrupt the next one, exactly as with a real re-read.
    return Ok<JsonObject>(deepClone(_values)! as JsonObject);
  }
}

/// A configuration layer that always fails, for testing the error path.
final class FailingConfigSource implements ConfigSource {
  /// Creates a layer failing with [code] and [message].
  const FailingConfigSource({
    this.name = 'failing',
    this.code = ConfigProblemCode.sourceUnreadable,
    this.message = 'fake layer failure',
  });

  /// Diagnostic label reported in the envelope's `data.source`.
  final String name;

  /// The failure code this layer reports.
  final ConfigProblemCode code;

  /// The failure message this layer reports.
  final String message;

  @override
  Future<Result<JsonObject>> load() async => configFailure<JsonObject>(
    code: code,
    message: message,
    details: <String, Object?>{'source': name},
  );
}

/// A deterministic landscape source.
final class FakeLandscapeSource implements LandscapeSource {
  /// Creates a source reporting [value]; pass `''` to fake a missing define.
  const FakeLandscapeSource(this.value);

  /// The landscape identity this source reports.
  final String value;

  @override
  String read() => value;
}

/// Builds a valid [DieneConfig] through the production schema path.
///
/// A stub built here has been through the SAME [ConfigSchema.validate] a real
/// load goes through, so it cannot be shaped like a configuration the loader
/// would have rejected — the failure mode of hand-constructing stubs.
final class ConfigStubBuilder {
  final Map<String, Object?> _raw = <String, Object?>{};
  final List<ConfigBlockSchema> _blocks = <ConfigBlockSchema>[];

  /// Adds [block] with the raw [values] it should decode.
  ConfigStubBuilder add<T>(ConfigBlock<T> block, Map<String, Object?> values) {
    _blocks.add(block);
    _raw[block.key] = values;
    return this;
  }

  /// Adds a root key with NO composed block.
  ///
  /// Only useful with `rejectUnknownBlocks: false`, or to prove that an
  /// unknown key is rejected when it is `true`.
  ConfigStubBuilder addRaw(String key, Object? value) {
    _raw[key] = value;
    return this;
  }

  /// Validates the accumulated blocks and returns the stub.
  ///
  /// Throws [ConfigAssertionFailure] when the stub does not validate: a test
  /// fixture that cannot exist is a bug in the test, and surfacing it here —
  /// with the schema's own error list — beats an opaque failure later.
  DieneConfig build({bool rejectUnknownBlocks = true}) {
    final Result<DieneConfig> validated = ConfigSchema(
      blocks: _blocks,
      rejectUnknownBlocks: rejectUnknownBlocks,
    ).validate(_raw);
    return validated.match(
      ok: (DieneConfig config) => config,
      err: (Problem problem) => throw ConfigAssertionFailure(
        'ConfigStubBuilder produced an INVALID stub: '
        '${_describeProblem(problem)}',
      ),
    );
  }

  /// Validates the accumulated blocks and returns the raw `Result`.
  ///
  /// For a test that wants to assert the stub is rejected.
  Result<DieneConfig> tryBuild({bool rejectUnknownBlocks = true}) =>
      ConfigSchema(
        blocks: _blocks,
        rejectUnknownBlocks: rejectUnknownBlocks,
      ).validate(_raw);
}

/// Runs the full production layer ladder over in-memory sources.
///
/// This is the REAL [ConfigLoader] with fake layers — not a reimplementation —
/// so a behaviour proven through the harness is a behaviour of the shipped
/// loader. The meta suite depends on exactly that: it runs the same matrix
/// through this harness and through real YAML and compares.
final class FakeConfigHarness {
  /// Creates a harness over the given layer contents.
  FakeConfigHarness({
    required this.base,
    required this.schema,
    this.overlay,
    this.developmentOverride,
    this.defines = const <String, String>{},
    this.prefix = 'TEST_',
  }) : baseSource = FakeConfigSource(base),
       overlaySource = overlay == null ? null : FakeConfigSource(overlay),
       developmentSource = developmentOverride == null
           ? null
           : FakeConfigSource(developmentOverride);

  /// The base layer contents.
  final Map<String, Object?> base;

  /// The overlay layer contents, or `null` for no overlay.
  final Map<String, Object?>? overlay;

  /// The development layer contents, or `null` for no development override.
  final Map<String, Object?>? developmentOverride;

  /// The enumerated defines.
  final Map<String, String> defines;

  /// The define key prefix.
  final String prefix;

  /// The composed schema.
  final ConfigSchema schema;

  /// The fake standing in for the base layer.
  final FakeConfigSource baseSource;

  /// The fake standing in for the overlay layer, if any.
  final FakeConfigSource? overlaySource;

  /// The fake standing in for the development layer, if any.
  final FakeConfigSource? developmentSource;

  /// The loader this harness drives.
  ConfigLoader get loader => ConfigLoader(
    base: baseSource,
    overlay: overlaySource,
    developmentOverride: developmentSource,
    dartDefines: DartDefineOverrides(prefix: prefix, values: defines),
    schema: schema,
  );

  /// Runs the ladder.
  Future<Result<DieneConfig>> load() => loader.load();
}

/// Returns the [DieneConfig] in [result], or throws with the problem's details.
///
/// The diagnostic carries the envelope's status, title, and any schema error
/// list, because "expected Ok but got Err" without them is the least useful
/// failure message a config test can produce.
DieneConfig expectOkConfig(Result<DieneConfig> result) => result.match(
  ok: (DieneConfig config) => config,
  err: (Problem problem) => throw ConfigAssertionFailure(
    'Expected a valid configuration but the load FAILED: '
    '${_describeProblem(problem)}',
  ),
);

/// Returns the [Problem] in [result], or throws when it succeeded.
Problem expectErrConfig(Result<DieneConfig> result) => result.match(
  ok: (DieneConfig config) => throw ConfigAssertionFailure(
    'Expected the load to FAIL but it produced a valid configuration: '
    '${config.raw}',
  ),
  err: (Problem problem) => problem,
);

/// Asserts that [result] failed with the config-owned [code].
///
/// Returns the problem so a caller can make further assertions on `data`.
/// Throws [ConfigAssertionFailure] when the result succeeded, or when it failed
/// with a different code — including a `diene_core_utils` coercion problem,
/// whose code belongs to that package's vocabulary and is reported verbatim in
/// the diagnostic rather than being mistaken for a config code.
Problem assertConfigProblem(
  Result<DieneConfig> result,
  ConfigProblemCode code,
) {
  final Problem problem = expectErrConfig(result);
  final Option<ConfigProblemCode> actual = configProblemCode(problem);
  final bool matches = actual.match(
    some: (ConfigProblemCode found) => found == code,
    none: () => false,
  );
  if (!matches) {
    throw ConfigAssertionFailure(
      'Expected config problem "${code.wireId}" but found '
      '"${problem.data['code']}": ${_describeProblem(problem)}',
    );
  }
  return problem;
}

/// Asserts that [config] exposes [expected] for [block]'s typed slice.
///
/// Equality is the block type's own `==`, so a value type without value
/// equality compares by identity — which is the type's contract, not this
/// helper's to override.
void assertConfigSlice<T>(
  DieneConfig config,
  ConfigBlock<T> block,
  T expected,
) {
  final T actual = config.slice<T>(block);
  if (actual != expected) {
    throw ConfigAssertionFailure(
      'Expected slice "${block.key}" to be <$expected> but found <$actual>.',
    );
  }
}

String _describeProblem(Problem problem) {
  final Object? errors = problem.data['errors'];
  final String suffix = errors is List<Object?>
      ? '\n- ${errors.join('\n- ')}'
      : '';
  return '${problem.status} ${problem.title} (${problem.detail})$suffix';
}
