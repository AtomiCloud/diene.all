import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'auth/demo_auth_gateway.dart';
import 'auth/logto_auth_gateway.dart';
import 'auth/session_controller.dart';
import 'config/app_config.dart';
import 'config/app_settings_controller.dart';
import 'i18n/translations.g.dart';
import 'notifications/notification_service.dart';
import 'onboarding/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppConfig config = await loadAppConfig();
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  LocaleSettings.setLocaleRawSync(config.locale.defaultLocale);
  final AppSettingsController settings = AppSettingsController(
    config: config,
    preferences: preferences,
  );
  final SingleRegionHomePicker homePicker = SingleRegionHomePicker(
    gateway: MemoryHomeClaimGateway(),
    landscape: config.identity.landscape,
  );
  final OnboardingCoordinator onboarding = OnboardingCoordinator(
    homePicker: homePicker,
    gateway: DemoOnboardingGateway(),
    backendId: config.onboarding.backendId,
  );
  final AuthProvider auth = config.auth.demoMode
      ? DemoAuthProvider(
          accessLifetime: config.session.accessLifetime,
          refreshLifetime: config.session.refreshLifetime,
        )
      : logtoAuthProvider(config);
  final SessionController session = SessionController(
    provider: auth,
    onboarding: onboarding,
    accessLifetime: config.session.accessLifetime,
    refreshLifetime: config.session.refreshLifetime,
  );
  await NotificationService(
    config: config,
    gateway: const FirebaseMessagingGateway(),
  ).initialize();
  runApp(
    DieneApp(
      config: config,
      settings: settings,
      session: session,
      preferences: preferences,
    ),
  );
}
