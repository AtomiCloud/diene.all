import 'dart:convert';
import 'package:diene_flutter_base/config/app_config.dart';
import 'package:diene_flutter_base/config/app_settings_controller.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deepMerge applies nested overlay without dropping base keys', () {
    final Map<String, Object?> result = deepMerge(
      <String, Object?>{
        'theme': <String, Object?>{'mode': 'system', 'primary': '#000000'},
      },
      <String, Object?>{
        'theme': <String, Object?>{'primary': '#FFFFFF'},
      },
    );

    expect(result, <String, Object?>{
      'theme': <String, Object?>{'mode': 'system', 'primary': '#FFFFFF'},
    });
  });

  test('loader applies base then flavor then define overrides', () async {
    final AppConfigLoader loader = AppConfigLoader.forTesting(
      landscape: 'pichu',
      bundle: _MemoryAssetBundle(<String, String>{
        'config/base.yaml': _baseYaml,
        'config/pichu.yaml': _pichuYaml,
      }),
    );

    final AppConfig config = await loader.load(
      defines: const <String, String>{
        'appName': 'CI Brand',
        'apiBaseUrl': 'https://override.example.invalid',
        'themeMode': 'dark',
      },
    );

    expect(config.identity.landscape, 'pichu');
    expect(config.branding.appName, 'CI Brand');
    expect(config.branding.shortName, 'Diene');
    expect(config.api.baseUrl, Uri.parse('https://override.example.invalid'));
    expect(config.theme.mode, ConfiguredThemeMode.dark);
    expect(config.theme.primary, 0xFFFF0000);
  });

  test('loader rejects runtime-selected unknown landscapes', () async {
    final AppConfigLoader loader = AppConfigLoader.forTesting(
      landscape: 'hostname-derived',
      bundle: _MemoryAssetBundle(const <String, String>{}),
    );

    await expectLater(loader.load(), throwsA(isA<StateError>()));
  });

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
