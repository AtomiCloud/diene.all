import 'package:diene_flutter_base/config/app_config.dart';

AppConfig testConfig({
  String landscape = 'lapras',
  ConfiguredThemeMode themeMode = ConfiguredThemeMode.system,
  bool notificationsEnabled = false,
}) => AppConfig(
  identity: AppIdentityConfig(
    landscape: landscape,
    platform: 'platform',
    service: 'service',
    module: 'app',
    version: '1.0.0',
  ),
  branding: BrandingConfig(
    appName: 'Diene Mobile ($landscape)',
    shortName: 'Diene',
    logoAsset: 'assets/brand/logo.svg',
    iconAsset: 'assets/brand/icon-$landscape.png',
  ),
  theme: ThemeConfig(
    mode: themeMode,
    primary: 0xFF0EA5A8,
    secondary: 0xFFF97316,
    surfaceTint: 0xFF0C7C70,
    radius: 20,
  ),
  locale: const LocaleConfig(
    defaultLocale: 'en',
    supportedLocales: <String>['en', 'es'],
  ),
  auth: AuthConfig(
    demoMode: true,
    endpoint: Uri.parse('https://auth.example.invalid'),
    clientId: 'mobile-client',
    resource: Uri.parse('https://api.example.invalid'),
    redirectUri: Uri.parse(
      'cloud.atomi.$landscape.platform.service.app://callback',
    ),
    scopes: const <String>['openid', 'offline_access'],
  ),
  session: const SessionConfig(
    accessLifetime: Duration(minutes: 10),
    refreshLifetime: Duration(days: 14),
  ),
  api: ApiConfig(baseUrl: Uri.parse('https://api.example.invalid')),
  notifications: NotificationConfig(
    enabled: notificationsEnabled,
    topic: 'service-updates',
  ),
  onboarding: const OnboardingConfig(backendId: 'primary'),
);
