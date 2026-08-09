import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/translations.g.dart';
import 'app_config.dart';

final class AppSettingsController extends ChangeNotifier {
  AppSettingsController({required this.config, required this.preferences}) {
    _themeMode = _readThemeMode() ?? _configuredThemeMode(config.theme.mode);
    _locale = Locale(
      preferences.getString(_localeKey) ?? config.locale.defaultLocale,
    );
    _primary = Color(preferences.getInt(_primaryKey) ?? config.theme.primary);
  }

  static const String _themeKey = 'settings.theme';
  static const String _localeKey = 'settings.locale';
  static const String _primaryKey = 'settings.primary';

  final AppConfig config;
  final SharedPreferences preferences;
  late ThemeMode _themeMode;
  late Locale _locale;
  late Color _primary;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  Color get primary => _primary;

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    await preferences.setString(_themeKey, value.name);
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    if (_locale == value) {
      return;
    }
    if (!config.locale.supportedLocales.contains(value.languageCode)) {
      throw ArgumentError.value(value, 'value', 'Unsupported locale');
    }
    _locale = value;
    await preferences.setString(_localeKey, value.languageCode);
    await LocaleSettings.setLocaleRaw(value.languageCode);
    notifyListeners();
  }

  Future<void> setPrimary(Color value) async {
    if (_primary == value) {
      return;
    }
    _primary = value;
    await preferences.setInt(_primaryKey, value.toARGB32());
    notifyListeners();
  }

  Future<void> reset() async {
    await preferences.remove(_themeKey);
    await preferences.remove(_localeKey);
    await preferences.remove(_primaryKey);
    _themeMode = _configuredThemeMode(config.theme.mode);
    _locale = Locale(config.locale.defaultLocale);
    _primary = Color(config.theme.primary);
    await LocaleSettings.setLocaleRaw(config.locale.defaultLocale);
    notifyListeners();
  }

  ThemeMode? _readThemeMode() {
    final String? value = preferences.getString(_themeKey);
    return value == null ? null : ThemeMode.values.byName(value);
  }
}

ThemeMode _configuredThemeMode(ConfiguredThemeMode value) => switch (value) {
  ConfiguredThemeMode.light => ThemeMode.light,
  ConfiguredThemeMode.dark => ThemeMode.dark,
  ConfiguredThemeMode.system => ThemeMode.system,
};
