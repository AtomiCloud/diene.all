import 'dart:convert';
import 'package:diene_config/diene_config.dart';
import 'package:diene_flutter_base/config/app_config.dart';
import 'package:diene_flutter_base/config/app_settings_controller.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final String? value = assets[key];
    if (value == null) {
      throw FlutterError('Missing test asset: $key');
    }
    return Uint8List.fromList(utf8.encode(value)).buffer.asByteData();
  }
}

/// Classifies a failure through the published, provenance-checked
/// [configProblemCode] so a test can only pass when the engine's own loader or
/// schema produced the `Err` — never a look-alike thrown from app code.
ConfigProblemCode? _problemCode(Problem problem) => configProblemCode(
  problem,
).match(some: (ConfigProblemCode code) => code, none: () => null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loader composes base then overlay then canonical nested defines',
    () async {
      final Result<AppConfig> result = await loadAppConfigResult(
        landscapeName: 'pichu',
        bundle: _MemoryAssetBundle(<String, String>{
          'config/base.yaml': _baseYaml,
          'config/pichu.yaml': _pichuYaml,
        }),
        defines: const <String, String>{
          'FLUTTER_BASE_BRANDING__APPNAME': 'CI Brand',
          'FLUTTER_BASE_API__BASEURL': 'https://override.example.invalid',
          'FLUTTER_BASE_THEME__MODE': 'dark',
        },
      );

      expect(result, isA<Ok<AppConfig>>());
      final AppConfig config = result.unwrap();

      // Overlay wins over base.
      expect(config.identity.landscape, 'pichu');
      expect(config.theme.primary, 0xFFFF0000);
      // Canonically prefixed defines win over overlay and base (last layer).
      expect(config.branding.appName, 'CI Brand');
      expect(config.api.baseUrl, Uri.parse('https://override.example.invalid'));
      expect(config.theme.mode, ConfiguredThemeMode.dark);
      // Base-only values survive every layer untouched.
      expect(config.branding.shortName, 'Diene');
      expect(config.session.accessLifetime, const Duration(minutes: 10));
      expect(config.onboarding.backendId, 'primary');
    },
  );

  test(
    'loader reports sourceUnreadable for an unknown runtime landscape',
    () async {
      final Result<AppConfig> result = await loadAppConfigResult(
        landscapeName: 'hostname-derived',
        bundle: _MemoryAssetBundle(<String, String>{
          'config/base.yaml': _baseYaml,
          // No config/hostname-derived.yaml: the selected overlay is absent.
        }),
      );

      expect(result, isA<Err<AppConfig>>());
      expect(
        _problemCode(result.unwrapErr()),
        ConfigProblemCode.sourceUnreadable,
      );
    },
  );

  test('compatibility load translates legacy injected define names', () async {
    final AppConfig config = await loadAppConfig(
      landscapeName: 'pichu',
      bundle: _MemoryAssetBundle(<String, String>{
        'config/base.yaml': _baseYaml,
        'config/pichu.yaml': _pichuYaml,
      }),
      defines: const <String, String>{
        'appName': 'Legacy Brand',
        'apiBaseUrl': 'https://legacy.example.invalid',
        'themeMode': 'dark',
      },
    );

    expect(config.branding.appName, 'Legacy Brand');
    expect(config.api.baseUrl, Uri.parse('https://legacy.example.invalid'));
    expect(config.theme.mode, ConfiguredThemeMode.dark);
  });

  test('loader reports landscapeMissing for a blank selector', () async {
    final Result<AppConfig> result = await loadAppConfigResult(
      landscapeName: '',
      bundle: _MemoryAssetBundle(const <String, String>{}),
    );

    expect(result, isA<Err<AppConfig>>());
    expect(
      _problemCode(result.unwrapErr()),
      ConfigProblemCode.landscapeMissing,
    );
  });

  test(
    'loader reports schemaInvalid for an unknown configuration root',
    () async {
      final Result<AppConfig> result = await loadAppConfigResult(
        landscapeName: 'lapras',
        bundle: _MemoryAssetBundle(<String, String>{
          'config/base.yaml': _baseYamlWithUnknownRoot,
          'config/lapras.yaml': '',
        }),
      );

      expect(result, isA<Err<AppConfig>>());
      expect(_problemCode(result.unwrapErr()), ConfigProblemCode.schemaInvalid);
    },
  );

  test('settings persist live theme, locale, and color controls', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final AppSettingsController settings = AppSettingsController(
      config: testConfig(),
      preferences: preferences,
    );
    int notifications = 0;
    settings.addListener(() => notifications += 1);

    await settings.setThemeMode(ThemeMode.dark);
    await settings.setLocale(const Locale('es'));
    await settings.setPrimary(const Color(0xFF112233));

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, const Locale('es'));
    expect(settings.primary, const Color(0xFF112233));
    expect(notifications, 3);
    expect(preferences.getString('settings.theme'), 'dark');
    expect(preferences.getString('settings.locale'), 'es');
    expect(preferences.getInt('settings.primary'), 0xFF112233);
  });
}

const String _baseYaml = '''
app: {landscape: lapras, platform: platform, service: service, module: app, version: 1.0.0}
branding: {appName: Base, shortName: Diene, logoAsset: logo.svg, iconAsset: icon.png}
theme: {mode: system, primary: '#000000', secondary: '#00FF00', surfaceTint: '#0000FF', radius: 20}
locale: {defaultLocale: en, supportedLocales: [en, es]}
auth:
  demoMode: true
  endpoint: https://auth.example.invalid
  clientId: client
  resource: https://api.example.invalid
  redirectUri: cloud.atomi.lapras.platform.service.app://callback
  scopes: [openid, offline_access]
session: {accessMinutes: 10, refreshDays: 14}
api: {baseUrl: https://api.example.invalid}
notifications: {enabled: false, topic: updates}
onboarding: {backendId: primary}
''';

const String _pichuYaml = '''
app: {landscape: pichu}
branding: {appName: Flavor}
theme: {primary: '#FF0000'}
api: {baseUrl: https://pichu.example.invalid}
auth: {redirectUri: cloud.atomi.pichu.platform.service.app://callback}
''';

const String _baseYamlWithUnknownRoot =
    '$_baseYaml\nmystery: {surprise: true}\n';
