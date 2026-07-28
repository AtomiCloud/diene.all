import 'package:diene_core_utils/diene_core_utils.dart' show deepMerge;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

// Re-export the C0 §3 layered merge so callers that layer config maps (and the
// config test) get the single-source implementation, not a local reimplementation.
export 'package:diene_core_utils/diene_core_utils.dart' show deepMerge;

enum ConfiguredThemeMode { light, dark, system }

final class AppConfig {
  const AppConfig({
    required this.identity,
    required this.branding,
    required this.theme,
    required this.locale,
    required this.auth,
    required this.session,
    required this.api,
    required this.notifications,
    required this.onboarding,
  });

  factory AppConfig.fromMap(Map<String, Object?> value) => AppConfig(
    identity: AppIdentityConfig.fromMap(_map(value, 'app')),
    branding: BrandingConfig.fromMap(_map(value, 'branding')),
    theme: ThemeConfig.fromMap(_map(value, 'theme')),
    locale: LocaleConfig.fromMap(_map(value, 'locale')),
    auth: AuthConfig.fromMap(_map(value, 'auth')),
    session: SessionConfig.fromMap(_map(value, 'session')),
    api: ApiConfig.fromMap(_map(value, 'api')),
    notifications: NotificationConfig.fromMap(_map(value, 'notifications')),
    onboarding: OnboardingConfig.fromMap(_map(value, 'onboarding')),
  );

  final AppIdentityConfig identity;
  final BrandingConfig branding;
  final ThemeConfig theme;
  final LocaleConfig locale;
  final AuthConfig auth;
  final SessionConfig session;
  final ApiConfig api;
  final NotificationConfig notifications;
  final OnboardingConfig onboarding;
}

final class AppIdentityConfig {
  const AppIdentityConfig({
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
    required this.version,
  });

  factory AppIdentityConfig.fromMap(Map<String, Object?> value) =>
      AppIdentityConfig(
        landscape: _string(value, 'landscape'),
        platform: _string(value, 'platform'),
        service: _string(value, 'service'),
        module: _string(value, 'module'),
        version: _string(value, 'version'),
      );

  final String landscape;
  final String platform;
  final String service;
  final String module;
  final String version;
}

final class BrandingConfig {
  const BrandingConfig({
    required this.appName,
    required this.shortName,
    required this.logoAsset,
    required this.iconAsset,
  });

  factory BrandingConfig.fromMap(Map<String, Object?> value) => BrandingConfig(
    appName: _string(value, 'appName'),
    shortName: _string(value, 'shortName'),
    logoAsset: _string(value, 'logoAsset'),
    iconAsset: _string(value, 'iconAsset'),
  );

  final String appName;
  final String shortName;
  final String logoAsset;
  final String iconAsset;
}

final class ThemeConfig {
  const ThemeConfig({
    required this.mode,
    required this.primary,
    required this.secondary,
    required this.surfaceTint,
    required this.radius,
  });

  factory ThemeConfig.fromMap(Map<String, Object?> value) => ThemeConfig(
    mode: ConfiguredThemeMode.values.byName(_string(value, 'mode')),
    primary: _hex(value, 'primary'),
    secondary: _hex(value, 'secondary'),
    surfaceTint: _hex(value, 'surfaceTint'),
    radius: _number(value, 'radius').toDouble(),
  );

  final int primary;
  final int secondary;
  final int surfaceTint;
  final double radius;
  final ConfiguredThemeMode mode;
}

final class LocaleConfig {
  const LocaleConfig({
    required this.defaultLocale,
    required this.supportedLocales,
  });

  factory LocaleConfig.fromMap(Map<String, Object?> value) {
    final List<Object?> supported = _list(value, 'supportedLocales');
    return LocaleConfig(
      defaultLocale: _string(value, 'defaultLocale'),
      supportedLocales: supported
          .map((Object? item) => item.toString())
          .toList(growable: false),
    );
  }

  final String defaultLocale;
  final List<String> supportedLocales;
}

final class AuthConfig {
  const AuthConfig({
    required this.demoMode,
    required this.endpoint,
    required this.clientId,
    required this.resource,
    required this.redirectUri,
    required this.scopes,
  });

  factory AuthConfig.fromMap(Map<String, Object?> value) => AuthConfig(
    demoMode: _boolean(value, 'demoMode'),
    endpoint: Uri.parse(_string(value, 'endpoint')),
    clientId: _string(value, 'clientId'),
    resource: Uri.parse(_string(value, 'resource')),
    redirectUri: Uri.parse(_string(value, 'redirectUri')),
    scopes: _list(
      value,
      'scopes',
    ).map((Object? item) => item.toString()).toList(growable: false),
  );

  final bool demoMode;
  final Uri endpoint;
  final String clientId;
  final Uri resource;
  final Uri redirectUri;
  final List<String> scopes;
}

final class SessionConfig {
  const SessionConfig({
    required this.accessLifetime,
    required this.refreshLifetime,
  });

  factory SessionConfig.fromMap(Map<String, Object?> value) => SessionConfig(
    accessLifetime: Duration(minutes: _number(value, 'accessMinutes').toInt()),
    refreshLifetime: Duration(days: _number(value, 'refreshDays').toInt()),
  );

  final Duration accessLifetime;
  final Duration refreshLifetime;
}

final class ApiConfig {
  const ApiConfig({required this.baseUrl});

  factory ApiConfig.fromMap(Map<String, Object?> value) =>
      ApiConfig(baseUrl: Uri.parse(_string(value, 'baseUrl')));

  final Uri baseUrl;
}

final class NotificationConfig {
  const NotificationConfig({required this.enabled, required this.topic});

  factory NotificationConfig.fromMap(Map<String, Object?> value) =>
      NotificationConfig(
        enabled: _boolean(value, 'enabled'),
        topic: _string(value, 'topic'),
      );

  final bool enabled;
  final String topic;
}

final class OnboardingConfig {
  const OnboardingConfig({required this.backendId});

  factory OnboardingConfig.fromMap(Map<String, Object?> value) =>
      OnboardingConfig(backendId: _string(value, 'backendId'));

  final String backendId;
}

final class AppConfigLoader {
  AppConfigLoader({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle,
      _selectedLandscape = compiledLandscape;

  @visibleForTesting
  AppConfigLoader.forTesting({required String landscape, AssetBundle? bundle})
    : bundle = bundle ?? rootBundle,
      _selectedLandscape = landscape;

  static const Set<String> supportedLandscapes = <String>{
    'lapras',
    'pichu',
    'pikachu',
    'raichu',
  };
  static const String compiledLandscape = String.fromEnvironment(
    'FLUTTER_BASE_LANDSCAPE',
    defaultValue: 'lapras',
  );

  final AssetBundle bundle;
  final String _selectedLandscape;

  Future<AppConfig> load({
    Map<String, String> defines = const <String, String>{},
  }) async {
    final String selected = _selectedLandscape;
    if (!supportedLandscapes.contains(selected)) {
      throw StateError('Unsupported build-time landscape: $selected');
    }
    final Map<String, Object?> base = await _loadYaml('config/base.yaml');
    final Map<String, Object?> overlay = await _loadYaml(
      'config/$selected.yaml',
    );
    final Map<String, Object?> merged = deepMerge(base, overlay);
    final Map<String, Object?> configured = deepMerge(
      merged,
      _compileTimeOverrides(defines),
    );
    return AppConfig.fromMap(configured);
  }

  Future<Map<String, Object?>> _loadYaml(String path) async {
    final Object? document = loadYaml(await bundle.loadString(path));
    return _plainMap(document);
  }

  Map<String, Object?> _compileTimeOverrides(Map<String, String> injected) {
    const Map<String, String> compiled = <String, String>{
      'appName': String.fromEnvironment('FLUTTER_BASE_APP_NAME'),
      'primary': String.fromEnvironment('FLUTTER_BASE_THEME_PRIMARY'),
      'secondary': String.fromEnvironment('FLUTTER_BASE_THEME_SECONDARY'),
      'themeMode': String.fromEnvironment('FLUTTER_BASE_THEME_MODE'),
      'apiBaseUrl': String.fromEnvironment('FLUTTER_BASE_API_BASE_URL'),
      'authEndpoint': String.fromEnvironment('FLUTTER_BASE_AUTH_ENDPOINT'),
      'authClientId': String.fromEnvironment('FLUTTER_BASE_AUTH_CLIENT_ID'),
      'authResource': String.fromEnvironment('FLUTTER_BASE_AUTH_RESOURCE'),
      'authRedirectUri': String.fromEnvironment(
        'FLUTTER_BASE_AUTH_REDIRECT_URI',
      ),
      'defaultLocale': String.fromEnvironment('FLUTTER_BASE_DEFAULT_LOCALE'),
      'notificationsEnabled': String.fromEnvironment(
        'FLUTTER_BASE_NOTIFICATIONS_ENABLED',
      ),
      'version': String.fromEnvironment(
        'FLUTTER_BASE_VERSION',
        defaultValue: '1.0.0',
      ),
    };
    final Map<String, String> values = <String, String>{
      ...compiled,
      ...injected,
    };
    final Map<String, Object?> overrides = <String, Object?>{
      'app': <String, Object?>{'version': values['version']},
    };
    _put(overrides, <String>['branding', 'appName'], values['appName']);
    _put(overrides, <String>['theme', 'primary'], values['primary']);
    _put(overrides, <String>['theme', 'secondary'], values['secondary']);
    _put(overrides, <String>['theme', 'mode'], values['themeMode']);
    _put(overrides, <String>['api', 'baseUrl'], values['apiBaseUrl']);
    _put(overrides, <String>['auth', 'endpoint'], values['authEndpoint']);
    _put(overrides, <String>['auth', 'clientId'], values['authClientId']);
    _put(overrides, <String>['auth', 'resource'], values['authResource']);
    _put(overrides, <String>['auth', 'redirectUri'], values['authRedirectUri']);
    _put(overrides, <String>[
      'locale',
      'defaultLocale',
    ], values['defaultLocale']);
    final String? notifications = values['notificationsEnabled'];
    if (notifications != null && notifications.isNotEmpty) {
      _put(overrides, <String>[
        'notifications',
        'enabled',
      ], notifications == 'true');
    }
    return overrides;
  }
}

Map<String, Object?> _plainMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('Configuration root must be a map');
  }
  return value.map(
    (Object? key, Object? item) => MapEntry(key.toString(), _plainValue(item)),
  );
}

Object? _plainValue(Object? value) => switch (value) {
  final Map<Object?, Object?> map => map.map(
    (Object? key, Object? item) => MapEntry(key.toString(), _plainValue(item)),
  ),
  final List<Object?> list => list.map(_plainValue).toList(growable: false),
  _ => value,
};

Map<String, Object?> _map(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! Map<String, Object?>) {
    throw FormatException('Configuration key $key must be a map');
  }
  return item;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! List<Object?>) {
    throw FormatException('Configuration key $key must be a list');
  }
  return item;
}

String _string(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! String || item.isEmpty) {
    throw FormatException('Configuration key $key must be a non-empty string');
  }
  return item;
}

num _number(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! num) {
    throw FormatException('Configuration key $key must be a number');
  }
  return item;
}

bool _boolean(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! bool) {
    throw FormatException('Configuration key $key must be a boolean');
  }
  return item;
}

int _hex(Map<String, Object?> value, String key) {
  final String raw = _string(value, key);
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) {
    throw FormatException('Configuration key $key must be #RRGGBB');
  }
  return int.parse('FF${raw.substring(1)}', radix: 16);
}

void _put(Map<String, Object?> root, List<String> path, Object? value) {
  if (value == null || (value is String && value.isEmpty)) {
    return;
  }
  final String section = path.first;
  final Map<String, Object?> target =
      root.putIfAbsent(section, () => <String, Object?>{})!
          as Map<String, Object?>;
  target[path.last] = value;
}
