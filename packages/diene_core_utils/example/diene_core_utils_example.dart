// A single pass through every group of the diene_core_utils surface: identity
// strings, the C0 §3 configuration ladder over an injected Vfs seam, and the
// C0 §1 temporal wire forms.
//
// Run it with:
//   dart run example/diene_core_utils_example.dart
//
// This file prints, which the repository lints against in library code for good
// reason. An example's whole job is to show a reader what each call returns, so
// the lint is suppressed HERE and nowhere else; `lib/` stays print-free.
// ignore_for_file: avoid_print

import 'package:diene_core_utils/c0_temporal.dart' show c0TemporalContract;
import 'package:diene_core_utils/diene_core_utils.dart' hide c0TemporalContract;
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

Future<void> main() async {
  _identity();
  _configuration();
  _temporal();
  await _configurationFromASeam();
  await _boundedConcurrency();
}

void _identity() {
  print('--- identity ---');

  // slugify is total: unmappable input yields '' rather than failing.
  print("slugify('Crème Brûlée')  = '${slugify('Crème Brûlée')}'");
  print("slugify('  --Hi--  ')    = '${slugify('  --Hi--  ')}'");
  print("slugify('!!!')           = '${slugify('!!!')}'");

  // namespacedKey CAN fail, so it returns a Result and never throws.
  print(
    'namespacedKey            = ${_show(namespacedKey('Diene', 'Core Utils'))}',
  );
  print('namespacedKey (empty ns) = ${_show(namespacedKey('---', 'key'))}');
}

void _configuration() {
  print('\n--- configuration (C0 §3) ---');

  final JsonObject base = <String, Object?>{
    'app': <String, Object?>{'displayName': 'base', 'retries': 1},
  };

  // Snake-cased defines land on the camelCase YAML key; __<digits> builds a
  // list; a blank value means UNSET and contributes nothing at all.
  final Result<JsonObject> defines = environmentToNestedMap(<String, String>{
    'ACME_APP__DISPLAY_NAME': 'production',
    'ACME_APP__TAGS__0': 'first',
    'ACME_APP__TAGS__1': 'second',
    'ACME_APP__RETRIES': '',
  }, prefix: 'ACME_');

  final JsonObject merged = deepMergeAll(<JsonObject>[base, defines.unwrap()]);
  print('merged                   = $merged');

  // Deterministic projection: sorted keys at every depth, list order preserved.
  print('stable projection        = ${_show(stableConfigObject(merged))}');

  // A cycle cannot be projected, and says so instead of hanging.
  final JsonObject cyclic = <String, Object?>{};
  cyclic['self'] = cyclic;
  print('cyclic input             = ${_show(stableConfig(cyclic))}');
}

void _temporal() {
  print('\n--- temporal wire forms (C0 §1) ---');
  const WireCodec codec = WireCodec();

  print('date  2026-07-26         = ${_show(codec.decodeDate('2026-07-26'))}');
  print('date  2026-02-30         = ${_show(codec.decodeDate('2026-02-30'))}');
  print('time  23:59:59           = ${_show(codec.decodeTime('23:59:59'))}');
  print(
    'dur   P1DT2.5H           = ${_show(codec.decodeDuration('P1DT2.5H'))}',
  );
  print(
    'zone  Asia/Singapore     = ${_show(codec.decodeTimezone('Asia/Singapore'))}',
  );
  print('zone  PST                = ${_show(codec.decodeTimezone('PST'))}');

  // Exactly ONE canonical instant spelling exists, so wire bytes are comparable.
  print(
    'instant …03Z             = ${_show(codec.decodeInstant('2026-07-26T01:02:03Z'))}',
  );
  print(
    'instant …03+00:00        = ${_show(codec.decodeInstant('2026-07-26T01:02:03+00:00'))}',
  );
  print(
    'normalise …+08:00        = ${_show(codec.normalizeInstant('2026-07-26T09:02:03+08:00'))}',
  );

  // The shared contract other Diene Dart packages drive conformance from.
  print(
    'shared C0 contract       = v${c0TemporalContract.provenance.contractVersion}, '
    'IANA ${c0TemporalContract.provenance.ianaRelease}, '
    '${c0TemporalContract.dates.valid.length} date vectors',
  );
}

Future<void> _configurationFromASeam() async {
  print('\n--- configuration over the injected Vfs seam ---');

  // InMemoryVfs ships in diene_interfaces' test_helper: no host filesystem is
  // touched, and production code sees only the Vfs INTERFACE either way.
  final InMemoryVfs vfs = InMemoryVfs();
  (await writeVfsText(
    vfs,
    '/etc/acme/base.kv',
    'name=base\nretries=1\n',
  )).unwrap();
  (await writeVfsText(vfs, '/etc/acme/production.kv', 'retries=5\n')).unwrap();

  final Result<JsonObject> config = await loadConfigLayers(vfs, <ConfigLayer>[
    const ConfigLayer(path: '/etc/acme/base.kv', parse: _parseKeyValue),
    const ConfigLayer(path: '/etc/acme/production.kv', parse: _parseKeyValue),
    // An absent OPTIONAL overlay contributes nothing; it is not an error.
    const ConfigLayer(
      path: '/etc/acme/local.kv',
      parse: _parseKeyValue,
      optional: true,
    ),
  ]);
  print('loaded                   = ${_show(config)}');

  // A required layer that is missing fails with the SEAM's own envelope.
  final Result<JsonObject> missing = await loadConfigLayers(vfs, <ConfigLayer>[
    const ConfigLayer(path: '/etc/acme/absent.kv', parse: _parseKeyValue),
  ]);
  print('missing required layer   = ${_show(missing)}');
}

Future<void> _boundedConcurrency() async {
  print('\n--- bounded concurrency ---');

  // Later items finish first, yet the result keeps INPUT order.
  final Result<List<String>> mapped = await mapWithConcurrency<int, String>(
    <int>[1, 2, 3, 4],
    2,
    (int value) async {
      (await sleep(Duration(milliseconds: 40 - value * 10))).unwrap();
      return Ok<String>('item-$value');
    },
  );
  print('mapWithConcurrency       = ${_show(mapped)}');

  // A negative duration fails as a value; no timer is ever scheduled.
  print(
    'sleep(-1s)               = ${_show(await sleep(const Duration(seconds: -1)))}',
  );
}

/// A tiny `key=value` reader: `diene_core_utils` ships no parser, because the
/// format is the consumer's choice while the merge semantics are C0 §3.
Result<JsonObject> _parseKeyValue(String text) {
  final JsonObject parsed = <String, Object?>{};
  for (final String line in text.split('\n')) {
    if (line.trim().isEmpty) {
      continue;
    }
    final int equals = line.indexOf('=');
    if (equals < 1) {
      return Err<JsonObject>(
        utilProblem(
          util: UtilName.vfs,
          code: UtilErrorCode.invalidFormat,
          operation: 'parseKeyValue',
          message: 'malformed key=value line',
        ),
      );
    }
    parsed[line.substring(0, equals)] = coerceEnvironmentScalar(
      line.substring(equals + 1),
    );
  }
  return Ok<JsonObject>(parsed);
}

/// Renders either channel of a `Result` for display.
String _show(Result<Object?> result) => result.match(
  ok: (Object? value) => 'Ok($value)',
  err: (Problem problem) => 'Err(${problem.status} ${problem.title})',
);
