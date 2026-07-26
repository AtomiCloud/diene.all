// Production dead-code root for the published diene_core_utils surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the public
// barrel (diene_core_utils.dart) as an entrypoint, so members reachable ONLY
// through the separately exported c0_temporal.dart sub-library, and public
// members no unit test happens to call, get reported as unused. Referencing
// every public export here keeps the production-only dead-code pass honest
// without any exclusion list (R12: two passes, no exclusions).
//
// deadcode.sh copies this file to bin/main.dart inside the production-only
// sandbox, so it lives in the member package where `package:diene_core_utils`
// resolves cleanly (and is excluded from the published archive by .pubignore).
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

Future<void> main() async {
  // --- identity -------------------------------------------------------------
  final String slug = slugify('Dead Code Entrypoint');
  final Result<String> key = namespacedKey('diene', slug);
  key
      .run((String composed) => _sink(composed))
      .mapErr((Problem problem) => problem);
  _sink(NamespacedKeyField.namespace.name);
  _sink(NamespacedKeyField.key.name);
  _sink(fuzzyIncludes(slug, 'dead'));

  // --- configuration --------------------------------------------------------
  final JsonObject base = <String, Object?>{
    'app': <String, Object?>{'name': 'base'},
  };
  final Result<JsonObject> defines = environmentToNestedMap(<String, String>{
    'ACME_APP__NAME': 'define',
    'ACME_APP__TAGS__0': 'first',
  }, prefix: 'ACME_');
  _sink(coerceEnvironmentScalar('true'));
  _sink(environmentPathSeparator);
  _sink(canonicalConfigKey('display-name'));
  _sink(configKeysMatch('display-name', 'displayName'));
  _sink(deepClone(base));
  _sink(isJsonObject(base));
  defines.run((JsonObject layer) {
    final JsonObject merged = deepMergeAll(<JsonObject>[base, layer]);
    _sink(deepMerge(base, layer));
    stableConfig(merged).run(_sink);
    stableConfigObject(merged).run(_sink);
  });

  // --- C0 temporal wire forms ----------------------------------------------
  const WireCodec codec = WireCodec();
  WireDate.of(
    2026,
    7,
    26,
  ).run((WireDate date) => _sink(codec.encodeDate(date)));
  WireDate.parse('2026-07-26').run(_sink);
  WireTime.of(1, 2, 3).run((WireTime time) => _sink(codec.encodeTime(time)));
  WireTime.parse('01:02:03').run(_sink);
  IsoDuration.parse(
    'PT0.5S',
  ).run((IsoDuration duration) => _sink(codec.encodeDuration(duration)));
  IanaTimezone.parse(
    'Asia/Singapore',
  ).run((IanaTimezone zone) => _sink(codec.encodeTimezone(zone)));
  codec.decodeDate('2026-07-26').run(_sink);
  codec.decodeTime('01:02:03').run(_sink);
  codec.decodeDuration('P1W').run(_sink);
  codec.decodeTimezone('UTC').run(_sink);
  codec.encodeInstant(DateTime.utc(2026, 7, 26)).run(_sink);
  codec.decodeInstant('2026-07-26T01:02:03Z').run(_sink);
  codec.normalizeInstant('2026-07-26T09:02:03+08:00').run(_sink);
  formatRfc3339Utc(DateTime.utc(2026, 7, 26)).run(_sink);
  parseRfc3339Utc('2026-07-26T01:02:03Z').run(_sink);
  normalizeRfc3339ToUtc('2026-07-26T09:02:03+08:00').run(_sink);
  _sink(isIanaTimeZone('UTC'));
  _sink(ianaTimeZoneRelease);
  _sink(wireDateGrammar);
  _sink(wireTimeGrammar);
  _sink(wireInstantGrammar);
  _sink(wireDurationGrammar);
  _sink(wireTimezoneGrammar);

  // --- the shared C0 temporal contract (c0_temporal.dart sub-library) -------
  const C0TemporalContract contract = c0TemporalContract;
  _sink(contract.digestPayload());
  _sink(contract.provenance.contractVersion);
  _sink(contract.provenance.c0Section);
  _sink(contract.provenance.c0Source);
  _sink(contract.provenance.ianaRelease);
  _sink(contract.provenance.ianaArchiveUrl);
  _sink(contract.provenance.ianaArchiveSha256);
  _sink(contract.provenance.contentSha256);
  _sink(contract.dates.valid);
  _sink(contract.dates.invalid);
  _sink(contract.times.valid);
  _sink(contract.times.invalid);
  _sink(contract.durations.valid);
  _sink(contract.durations.invalid);
  _sink(contract.timezones.valid);
  _sink(contract.timezones.invalid);
  _sink(contract.invalidInstants);
  for (final C0InstantVector vector in contract.instants) {
    _sink(vector.input);
    _sink(vector.canonicalUtc);
  }

  // --- problem vocabulary ---------------------------------------------------
  _sink(coreUtilsProblemVersion);
  for (final UtilName util in UtilName.values) {
    _sink(util.wireId);
  }
  for (final UtilErrorCode code in UtilErrorCode.values) {
    _sink(<Object?>[code.wireId, code.status, code.recoverable]);
  }
  _sink(
    utilProblem(
      util: UtilName.slug,
      code: UtilErrorCode.invalidInput,
      operation: 'deadcode',
      message: 'reference the builder',
    ),
  );
  _sink(
    utilFailure<void>(
      util: UtilName.record,
      code: UtilErrorCode.delegated,
      operation: 'deadcode',
      message: 'reference the sugar',
    ),
  );
  _sink(
    invalidUtilInput<void>(
      util: UtilName.timing,
      operation: 'deadcode',
      field: 'duration',
      message: 'reference the sugar',
    ),
  );
  _sink(
    invalidWireFormat<void>(
      operation: 'deadcode',
      expected: wireDateGrammar,
      value: 'nope',
    ),
  );

  // --- waiting and bounded concurrency -------------------------------------
  (await sleep(Duration.zero)).run(_sink);
  (await mapWithConcurrency<int, int>(
    <int>[1, 2, 3],
    2,
    (int value) async => Ok<int>(value * 2),
  )).run(_sink);

  // --- the diene_interfaces Vfs seam ---------------------------------------
  final InMemoryVfs vfs = InMemoryVfs();
  (await writeVfsText(vfs, '/config/base.json', '{}')).run(_sink);
  (await readVfsText(vfs, '/config/base.json')).run(_sink);
  (await readOptionalVfsText(vfs, '/config/absent.json')).run(_sink);
  const ConfigLayer layer = ConfigLayer(
    path: '/config/base.json',
    parse: _emptyLayer,
    optional: true,
  );
  _sink(<Object?>[layer.path, layer.optional]);
  (await loadConfigLayers(vfs, <ConfigLayer>[layer])).run(_sink);
}

Result<JsonObject> _emptyLayer(String text) =>
    Ok<JsonObject>(<String, Object?>{'length': text.length});

/// Consumes a value so the analyzer sees a real use without printing.
void _sink(Object? value) {
  if (value == null && DateTime.now().year < 0) {
    throw StateError('unreachable');
  }
}
