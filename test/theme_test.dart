import 'package:diene_flutter_base/config/app_config.dart';
import 'package:diene_flutter_base/config/app_settings_controller.dart';
import 'package:diene_flutter_base/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Material 3 light and dark themes carry the configured identity', () {
    final AppConfig config = testConfig();
    final ThemeData light = AppTheme.light(config, const Color(0xFF0EA5A8));
    final ThemeData dark = AppTheme.dark(config, const Color(0xFF0EA5A8));

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.textTheme.displayMedium!.fontFamily, 'Newsreader');
    expect(dark.textTheme.bodyMedium!.fontFamily, 'Atkinson');
  });

  for (final ThemeMode mode in ThemeMode.values) {
    test('configured ${mode.name} mode is honored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettingsController settings = AppSettingsController(
        config: testConfig(
          themeMode: switch (mode) {
            ThemeMode.light => ConfiguredThemeMode.light,
            ThemeMode.dark => ConfiguredThemeMode.dark,
            ThemeMode.system => ConfiguredThemeMode.system,
          },
        ),
        preferences: await SharedPreferences.getInstance(),
      );

      expect(settings.themeMode, mode);
    });
  }
}
