import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/services.dart';

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

/// Stable, file-level [ConfigBlock] instances — one per configuration root.
///
/// Identity matters: [DieneConfig.slice] keys decoded values by the block
/// INSTANCE that produced them, so the loader must both compose the schema and
/// slice the result through these very objects. They are declared once and
/// never reconstructed.
final ConfigBlock<AppIdentityConfig> _appBlock = ConfigBlock<AppIdentityConfig>(
  key: 'app',
  decode: AppIdentityConfig.fromMap,
);
final ConfigBlock<BrandingConfig> _brandingBlock = ConfigBlock<BrandingConfig>(
  key: 'branding',
  decode: BrandingConfig.fromMap,
);
final ConfigBlock<ThemeConfig> _themeBlock = ConfigBlock<ThemeConfig>(
  key: 'theme',
  decode: ThemeConfig.fromMap,
);
final ConfigBlock<LocaleConfig> _localeBlock = ConfigBlock<LocaleConfig>(
  key: 'locale',
  decode: LocaleConfig.fromMap,
);
final ConfigBlock<AuthConfig> _authBlock = ConfigBlock<AuthConfig>(
  key: 'auth',
  decode: AuthConfig.fromMap,
);
final ConfigBlock<SessionConfig> _sessionBlock = ConfigBlock<SessionConfig>(
  key: 'session',
  decode: SessionConfig.fromMap,
);
final ConfigBlock<ApiConfig> _apiBlock = ConfigBlock<ApiConfig>(
  key: 'api',
  decode: ApiConfig.fromMap,
);
final ConfigBlock<NotificationConfig> _notificationsBlock =
    ConfigBlock<NotificationConfig>(
      key: 'notifications',
      decode: NotificationConfig.fromMap,
    );
final ConfigBlock<OnboardingConfig> _onboardingBlock =
    ConfigBlock<OnboardingConfig>(
      key: 'onboarding',
      decode: OnboardingConfig.fromMap,
    );

/// The one strict schema composed from every app-owned block.
///
/// `rejectUnknownBlocks` defaults to `true`, so an unrecognised root key is a
/// validation failure (`schemaInvalid`) rather than a silently ignored typo.
final ConfigSchema _appConfigSchema = ConfigSchema(
  blocks: <ConfigBlockSchema>[
    _appBlock,
    _brandingBlock,
    _themeBlock,
    _localeBlock,
    _authBlock,
    _sessionBlock,
    _apiBlock,
    _notificationsBlock,
    _onboardingBlock,
  ],
);

/// Builds the typed [AppConfig] from a validated [DieneConfig] by slicing each
/// stable block instance the schema composed.
AppConfig _appConfigFromSlices(DieneConfig config) => AppConfig(
  identity: config.slice<AppIdentityConfig>(_appBlock),
  branding: config.slice<BrandingConfig>(_brandingBlock),
  theme: config.slice<ThemeConfig>(_themeBlock),
  locale: config.slice<LocaleConfig>(_localeBlock),
  auth: config.slice<AuthConfig>(_authBlock),
  session: config.slice<SessionConfig>(_sessionBlock),
  api: config.slice<ApiConfig>(_apiBlock),
  notifications: config.slice<NotificationConfig>(_notificationsBlock),
  onboarding: config.slice<OnboardingConfig>(_onboardingBlock),
);

/// Reads the deployed landscape selector from a single build-time define.
///
/// Preserves the legacy `FLUTTER_BASE_LANDSCAPE` selector while delegating the
/// blank-is-missing rule to the published [landscape] accessor: a blank value
/// becomes a `landscapeMissing` failure rather than an empty landscape.
final class _FlutterBaseLandscapeSource implements LandscapeSource {
  const _FlutterBaseLandscapeSource(this.value);

  final String value;

  @override
  String read() => value;
}

/// The landscapes shipped by this app.
///
/// Retained for source compatibility. Loading no longer rejects names outside
/// this inventory up front; the selected overlay reports a `sourceUnreadable`
/// result when it does not exist.
const Set<String> supportedLandscapes = <String>{
  'lapras',
  'pichu',
  'pikachu',
  'raichu',
};

/// Prefix shared by every enumerated `--dart-define`; matched
/// case-insensitively by the engine's ingress.
const String configDefinePrefix = 'FLUTTER_BASE_';

const Map<String, String> _legacyDefineKeys = <String, String>{
  'appName': 'FLUTTER_BASE_BRANDING__APPNAME',
  'primary': 'FLUTTER_BASE_THEME__PRIMARY',
  'secondary': 'FLUTTER_BASE_THEME__SECONDARY',
  'themeMode': 'FLUTTER_BASE_THEME__MODE',
  'apiBaseUrl': 'FLUTTER_BASE_API__BASEURL',
  'authEndpoint': 'FLUTTER_BASE_AUTH__ENDPOINT',
  'authClientId': 'FLUTTER_BASE_AUTH__CLIENTID',
  'authResource': 'FLUTTER_BASE_AUTH__RESOURCE',
  'authRedirectUri': 'FLUTTER_BASE_AUTH__REDIRECTURI',
  'defaultLocale': 'FLUTTER_BASE_LOCALE__DEFAULTLOCALE',
  'notificationsEnabled': 'FLUTTER_BASE_NOTIFICATIONS__ENABLED',
  'version': 'FLUTTER_BASE_APP__VERSION',
};

/// Build-time landscape policy holder.
///
/// The landscape MUST be baked at build/stamp time and never derived at runtime
/// (scripts/validate/landscape-policy.sh). Declaring it as a
/// `static const String.fromEnvironment` here is the compile-time source the
/// policy gate checks for.
abstract final class AppLandscape {
  /// The build-time landscape selector, defaulting to `lapras` for parity with
  /// the deployed flavor when no selector is injected.
  static const String compiledLandscape = String.fromEnvironment(
    'FLUTTER_BASE_LANDSCAPE',
    defaultValue: 'lapras',
  );
}

/// Loads and validates the layered configuration through the published
/// [ConfigLoader], unwrapping so startup callers get the app's typed
/// [AppConfig] directly. Prefer [loadAppConfigResult] when the failure must be
/// handled as a value.
///
/// [landscapeName] defaults to the compile-time
/// [AppLandscape.compiledLandscape]; tests pass an explicit landscape and a
/// memory [bundle].
Future<AppConfig> loadAppConfig({
  AssetBundle? bundle,
  String? landscapeName,
  Map<String, String> defines = const <String, String>{},
}) async => (await loadAppConfigResult(
  bundle: bundle,
  landscapeName: landscapeName,
  defines: defines,
)).unwrap();

/// Runs the published precedence ladder on [ConfigLoader] — base -> selected
/// overlay -> enumerated Dart defines -> a single final schema validation — and
/// returns the app's typed [AppConfig] or the failure as a value.
Future<Result<AppConfig>> loadAppConfigResult({
  AssetBundle? bundle,
  String? landscapeName,
  Map<String, String> defines = const <String, String>{},
}) async {
  final AssetBundle assets = bundle ?? rootBundle;
  final LandscapeSource source = _FlutterBaseLandscapeSource(
    landscapeName ?? AppLandscape.compiledLandscape,
  );
  final Result<String> selected = landscape(source: source);
  switch (selected) {
    case Err<String>(problem: final Problem problem):
      return Err<AppConfig>(problem);
    case Ok<String>(value: final String name):
      final ConfigLoader loader = ConfigLoader(
        base: _yamlSource(assets, 'config/base.yaml'),
        overlay: _yamlSource(assets, 'config/$name.yaml'),
        dartDefines: DartDefineOverrides(
          prefix: configDefinePrefix,
          values: _defineValues(defines),
        ),
        schema: _appConfigSchema,
      );
      final Result<DieneConfig> loaded = await loader.load();
      return loaded.map(_appConfigFromSlices);
  }
}

YamlConfigSource _yamlSource(AssetBundle bundle, String path) =>
    YamlConfigSource(name: path, read: () => bundle.loadString(path));

/// Enumerates the legacy compile-time flags under canonical nested engine
/// keys, then layers any injected (already canonically prefixed) defines on
/// top. Blank values stay unset; malformed keys surface as `Err` from the
/// engine's define ingress.
Map<String, String> _defineValues(Map<String, String> injected) {
  final Map<String, String> normalizedInjected = <String, String>{};
  for (final MapEntry<String, String> entry in injected.entries) {
    final String? canonical = _legacyDefineKeys[entry.key];
    if (canonical != null) {
      normalizedInjected[canonical] = entry.value;
    }
  }
  for (final MapEntry<String, String> entry in injected.entries) {
    if (!_legacyDefineKeys.containsKey(entry.key)) {
      normalizedInjected[entry.key] = entry.value;
    }
  }

  return <String, String>{
    'FLUTTER_BASE_APP__VERSION': const String.fromEnvironment(
      'FLUTTER_BASE_VERSION',
      defaultValue: '1.0.0',
    ),
    'FLUTTER_BASE_BRANDING__APPNAME': const String.fromEnvironment(
      'FLUTTER_BASE_APP_NAME',
    ),
    'FLUTTER_BASE_THEME__PRIMARY': const String.fromEnvironment(
      'FLUTTER_BASE_THEME_PRIMARY',
    ),
    'FLUTTER_BASE_THEME__SECONDARY': const String.fromEnvironment(
      'FLUTTER_BASE_THEME_SECONDARY',
    ),
    'FLUTTER_BASE_THEME__MODE': const String.fromEnvironment(
      'FLUTTER_BASE_THEME_MODE',
    ),
    'FLUTTER_BASE_API__BASEURL': const String.fromEnvironment(
      'FLUTTER_BASE_API_BASE_URL',
    ),
    'FLUTTER_BASE_AUTH__ENDPOINT': const String.fromEnvironment(
      'FLUTTER_BASE_AUTH_ENDPOINT',
    ),
    'FLUTTER_BASE_AUTH__CLIENTID': const String.fromEnvironment(
      'FLUTTER_BASE_AUTH_CLIENT_ID',
    ),
    'FLUTTER_BASE_AUTH__RESOURCE': const String.fromEnvironment(
      'FLUTTER_BASE_AUTH_RESOURCE',
    ),
    'FLUTTER_BASE_AUTH__REDIRECTURI': const String.fromEnvironment(
      'FLUTTER_BASE_AUTH_REDIRECT_URI',
    ),
    'FLUTTER_BASE_LOCALE__DEFAULTLOCALE': const String.fromEnvironment(
      'FLUTTER_BASE_DEFAULT_LOCALE',
    ),
    'FLUTTER_BASE_NOTIFICATIONS__ENABLED': const String.fromEnvironment(
      'FLUTTER_BASE_NOTIFICATIONS_ENABLED',
    ),
    ...normalizedInjected,
  };
}

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
