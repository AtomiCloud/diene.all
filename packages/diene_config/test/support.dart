/// Shared fixtures for the `diene_config` suites.
///
/// Only genuinely shared vocabulary lives here — the sample block type every
/// suite decodes, and the two matchers that describe a `Result`'s channel.
/// Anything used by one suite stays in that suite, where a reader can see it.
library;

import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

/// The sample settings type the suites compose a block around.
final class AppSettings {
  const AppSettings({
    required this.name,
    required this.retries,
    required this.tags,
  });

  final String name;
  final int retries;
  final List<String> tags;

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.name == name &&
      other.retries == retries &&
      other.tags.length == tags.length &&
      _sameTags(other.tags);

  bool _sameTags(List<String> otherTags) {
    for (int index = 0; index < tags.length; index++) {
      if (tags[index] != otherTags[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, retries, Object.hashAll(tags));

  @override
  String toString() => 'AppSettings($name, $retries, $tags)';
}

/// The `app` block, with the validation the C0 §3 vectors assume:
/// a non-empty name and a non-negative retry count.
final ConfigBlock<AppSettings> appBlock = ConfigBlock<AppSettings>(
  key: 'app',
  decode: (Map<String, Object?> values) {
    final Object? name = values['name'];
    final Object? retries = values['retries'];
    if (name is! String || name.isEmpty) {
      throw FormatException('name must be a non-empty string, got $name');
    }
    if (retries is! int || retries < 0) {
      throw FormatException('retries must be a non-negative int, got $retries');
    }
    return AppSettings(
      name: name,
      retries: retries,
      tags: (values['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? tag) => '$tag')
          .toList(growable: false),
    );
  },
);

/// A schema composed of just [appBlock].
ConfigSchema appSchema({bool rejectUnknownBlocks = true}) => ConfigSchema(
  blocks: <ConfigBlockSchema>[appBlock],
  rejectUnknownBlocks: rejectUnknownBlocks,
);

/// Renders either channel of a `Result` for a failure message.
///
/// Every `expect` below passes this as its `reason`, so a red test names the
/// problem instead of only saying `Ok` was expected.
String describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'Ok($value)',
  err: (Problem problem) =>
      'Err(${problem.status} ${problem.title}; data=${problem.data})',
);

/// Matches an `Ok` result.
Matcher get isOk => predicate<Result<Object?>>(
  (Result<Object?> result) => result.isOk,
  'an Ok result',
);

/// Matches an `Err` result.
Matcher get isErr => predicate<Result<Object?>>(
  (Result<Object?> result) => result.isErr,
  'an Err result',
);
