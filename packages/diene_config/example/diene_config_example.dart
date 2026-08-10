// A single pass through the diene_config surface: the four-layer ladder, the
// service-composed schema, typed slices, the landscape accessor, and the
// failure channel.
//
// Run it with:
//   dart run example/diene_config_example.dart
//
// This file prints, which the repository lints against in library code for good
// reason. An example's whole job is to show a reader what each call returns, so
// the lint is suppressed HERE and nowhere else; `lib/` stays print-free.
// ignore_for_file: avoid_print

import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// An engine- or service-owned settings type.
///
/// In a real app this lives beside the code that READS it — in `auth_engine`
/// for auth settings, in `api_engine` for API settings — and the app composes
/// the exported blocks. `diene_config` never defines one.
final class ApiSettings {
  const ApiSettings({required this.baseUrl, required this.scopes});

  final Uri baseUrl;
  final List<String> scopes;

  @override
  String toString() => 'ApiSettings($baseUrl, $scopes)';
}

/// The block its owner exports next to [ApiSettings].
final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) {
    final Object? baseUrl = values['baseUrl'];
    if (baseUrl is! String || Uri.tryParse(baseUrl)?.hasScheme != true) {
      throw FormatException('baseUrl must be an absolute URI, got $baseUrl');
    }
    return ApiSettings(
      baseUrl: Uri.parse(baseUrl),
      scopes: (values['scopes'] as List<Object?>? ?? const <Object?>[])
          .map((Object? scope) => '$scope')
          .toList(growable: false),
    );
  },
);

/// A full base document: every overrideable path, with defaults.
const String baseYaml = '''
api:
  baseUrl: https://api.local.test
  scopes: [openid]
''';

/// A sparse landscape overlay: only what this landscape changes.
const String landscapeYaml = '''
api:
  baseUrl: https://api.lapras.atomi.cloud
''';

Future<void> main() async {
  await _theLadder();
  await _failuresAreValues();
  _theLandscapeAccessor();
}

Future<void> _theLadder() async {
  print('--- the four-layer ladder ---');

  final ConfigLoader loader = ConfigLoader(
    // 1. Full base YAML. A real app passes File(path).readAsString or
    //    rootBundle.loadString here; the package touches neither dart:io nor
    //    Flutter itself.
    base: YamlConfigSource.string(baseYaml, name: 'config/base.yaml'),
    // 2. One sparse flavor/landscape overlay.
    overlay: YamlConfigSource.string(landscapeYaml, name: 'config/lapras.yaml'),
    // 3. An optional development hook. Omit it (or pass null) in release.
    developmentOverride: YamlConfigSource.string(
      'api:\n  scopes: [openid, offline_access]\n',
      name: 'config/development.yaml',
    ),
    // 4. Enumerated --dart-define values, applied LAST. Dart has no runtime
    //    environment enumeration, so the app lists the keys it accepts.
    dartDefines: const DartDefineOverrides(
      prefix: 'ACME_',
      values: <String, String>{
        // Lists come ONLY from indexed keys — never JSON, never commas.
        'ACME_API__SCOPES__0': 'openid',
        'ACME_API__SCOPES__1': 'profile',
        // A blank define is UNSET and cannot erase the base value.
        'ACME_API__BASE_URL': '',
      },
    ),
    // 5. The service composes the root schema from engine-owned blocks.
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  );

  final Result<DieneConfig> loaded = await loader.load();
  print('loaded              = ${_show(loaded)}');

  loaded.run((DieneConfig config) {
    final ApiSettings api = config.slice(apiBlock);
    // The landscape overlay won the URL; the blank define did not erase it.
    print('typed slice         = $api');
    // The indexed defines replaced the development layer's list wholesale.
    print('scopes              = ${api.scopes}');
    print('raw slice           = ${_show(config.rawSlice('api'))}');
    print('stable projection   = ${_show(config.stableProjection())}');
  });
}

Future<void> _failuresAreValues() async {
  print('\n--- failures are values, not exceptions ---');

  // An unreadable layer: the read callback threw, so the layer is reported
  // rather than crashing the load.
  final Result<DieneConfig> unreadable = await ConfigLoader(
    base: YamlConfigSource(
      name: 'config/absent.yaml',
      read: () => throw StateError('asset not found'),
    ),
    dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();
  print('missing layer       = ${_show(unreadable)}');

  // An invalid FINAL tree. Validation runs once, at the end — a base that is
  // incomplete on its own is fine if a later layer completes it.
  final Result<DieneConfig> invalid = await ConfigLoader(
    base: YamlConfigSource.string('api:\n  baseUrl: not-a-uri\n'),
    dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();
  print('invalid final tree  = ${_show(invalid)}');

  // ...and the same base, repaired by a later layer, is accepted.
  final Result<DieneConfig> repaired = await ConfigLoader(
    base: YamlConfigSource.string('api:\n  baseUrl: not-a-uri\n'),
    dartDefines: const DartDefineOverrides(
      prefix: 'ACME_',
      values: <String, String>{'ACME_API__BASE_URL': 'https://api.test'},
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();
  print('repaired by define  = ${_show(repaired)}');

  // A malformed define key is reported with the core-utils coercion envelope,
  // UNCHANGED, so its precise vocabulary survives.
  final Result<DieneConfig> malformed = await ConfigLoader(
    base: YamlConfigSource.string(baseYaml),
    dartDefines: const DartDefineOverrides(
      prefix: 'ACME_',
      values: <String, String>{'ACME_API____BASE_URL': 'https://api.test'},
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();
  print('malformed define    = ${_show(malformed)}');
}

void _theLandscapeAccessor() {
  print('\n--- the landscape accessor ---');

  // A store build supplies --dart-define=DIENE_LANDSCAPE=<track>. The accessor
  // reads that define and NOTHING else: no hostname sniffing, no runtime probe.
  print(
    'injected            = '
    '${_show(landscape(source: const DartDefineLandscapeSource(value: 'lapras')))}',
  );

  // Without the define there is no identity, and it says so as a value.
  print('absent define       = ${_show(landscape())}');
}

/// Renders either channel of a `Result` for display.
String _show(Result<Object?> result) => result.match(
  ok: (Object? value) => 'Ok($value)',
  err: (Problem problem) =>
      'Err(${problem.status} ${problem.title}; data=${problem.data})',
);
