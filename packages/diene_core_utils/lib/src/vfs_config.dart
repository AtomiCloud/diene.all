/// Layered-configuration helpers over the `diene_interfaces` `Vfs` seam.
///
/// These are the only members that touch the outside world, and they do it
/// through the INJECTED `Vfs` interface type from `package:diene_interfaces` —
/// never `dart:io`. That keeps `diene_core_utils` platform-neutral (web, VM,
/// Flutter) and makes the whole surface testable against
/// `package:diene_interfaces/test_helper.dart`'s `InMemoryVfs` with no host
/// filesystem at all.
///
/// A `Vfs` failure is propagated UNCHANGED — the seam already mints an RFC 9457
/// envelope through the single C0 §2 builder, so re-wrapping it would bury the
/// real cause behind a second envelope. Only failures this library itself
/// detects get a `diene_core_utils` [Problem].
library;

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'merge.dart';
import 'util_problem.dart';

/// Reads [path] from [vfs] as UTF-8 text.
///
/// A thin, intention-revealing pass-through: it exists so consumers of this
/// package express "read a config layer" without importing the seam library
/// directly, exactly as the `lib/bun/core-utils` sibling's `readVfsTextFile`
/// does. The seam's failure is returned verbatim.
Future<Result<String>> readVfsText(Vfs vfs, String path) => vfs.readText(path);

/// Writes [contents] to [path] through [vfs] as UTF-8.
///
/// Missing parent directories are created, which is what a config or cache write
/// almost always wants; a caller needing the strict behaviour uses the seam
/// directly.
Future<Result<void>> writeVfsText(Vfs vfs, String path, String contents) =>
    vfs.writeText(path, contents, createParents: true);

/// Reads [path] from [vfs] and returns its text, or `null` when the path does
/// not exist.
///
/// An OPTIONAL configuration layer is the common case — a landscape overlay that
/// simply may not be present is not an error — so absence is modelled as a
/// successful `null` rather than a failure. Any other seam failure (permission,
/// I/O, not-a-file) still propagates unchanged, so a genuine misconfiguration is
/// never silently swallowed as "absent".
Future<Result<String?>> readOptionalVfsText(Vfs vfs, String path) async {
  final Result<bool> present = await vfs.exists(path);
  switch (present) {
    case Err<bool>(problem: final Problem problem):
      return Err<String?>(problem);
    case Ok<bool>(value: final bool exists):
      if (!exists) {
        return const Ok<String?>(null);
      }
  }
  final Result<String> text = await vfs.readText(path);
  return text.map((String value) => value);
}

/// One named configuration layer, lowest precedence first.
final class ConfigLayer {
  /// Describes a layer to load.
  const ConfigLayer({
    required this.path,
    required this.parse,
    this.optional = false,
  });

  /// The path handed to the `Vfs` seam.
  final String path;

  /// Turns this layer's text into a [JsonObject].
  ///
  /// Parsing is injected because `diene_core_utils` deliberately ships no YAML
  /// or JSON parser: the format is the consumer's choice (and `diene_config`
  /// owns the YAML story), while the PRECEDENCE and MERGE semantics are C0 §3
  /// and belong here.
  final Result<JsonObject> Function(String text) parse;

  /// Whether an absent path is acceptable.
  final bool optional;
}

/// Loads [layers] through [vfs] and deep-merges them in order.
///
/// This is the C0 §3 precedence ladder driven off a real filesystem seam:
/// earlier layers are the base, later layers override, and the merge is
/// [deepMergeAll], so key matching stays case- and separator-insensitive.
/// Loading stops at the FIRST failure and returns its [Problem] — a
/// half-merged configuration is never handed back. A missing layer marked
/// `optional` contributes nothing; a missing layer that is NOT optional fails
/// with the seam's own not-found envelope.
Future<Result<JsonObject>> loadConfigLayers(
  Vfs vfs,
  List<ConfigLayer> layers,
) async {
  final List<JsonObject> loaded = <JsonObject>[];
  for (final ConfigLayer layer in layers) {
    final String? text;
    if (layer.optional) {
      final Result<String?> optional = await readOptionalVfsText(
        vfs,
        layer.path,
      );
      switch (optional) {
        case Err<String?>(problem: final Problem problem):
          return Err<JsonObject>(problem);
        case Ok<String?>(value: final String? value):
          text = value;
      }
    } else {
      final Result<String> required = await vfs.readText(layer.path);
      switch (required) {
        case Err<String>(problem: final Problem problem):
          return Err<JsonObject>(problem);
        case Ok<String>(value: final String value):
          text = value;
      }
    }

    if (text == null) {
      continue;
    }

    final Result<JsonObject> parsed = layer.parse(text);
    switch (parsed) {
      case Err<JsonObject>(problem: final Problem problem):
        return Err<JsonObject>(problem);
      case Ok<JsonObject>(value: final JsonObject value):
        loaded.add(value);
    }
  }

  if (loaded.isEmpty) {
    return utilFailure<JsonObject>(
      util: UtilName.vfs,
      code: UtilErrorCode.invalidInput,
      operation: 'loadConfigLayers',
      message: 'no configuration layer was present',
      details: <String, Object?>{
        'paths': <String>[for (final ConfigLayer layer in layers) layer.path],
      },
    );
  }

  return Ok<JsonObject>(deepMergeAll(loaded));
}
