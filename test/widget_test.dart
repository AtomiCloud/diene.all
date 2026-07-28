import 'dart:async';

import 'package:diene_flutter_base/app.dart';
import 'package:diene_flutter_base/auth/session_controller.dart';
import 'package:diene_flutter_base/config/app_settings_controller.dart';
import 'package:diene_flutter_base/i18n/translations.g.dart';
import 'package:diene_flutter_base/onboarding/onboarding.dart';
import 'package:diene_flutter_base/widgets/amount_input.dart';
import 'package:diene_flutter_base/widgets/async_button.dart';
import 'package:diene_flutter_base/widgets/bottom_sheet_selector.dart';
import 'package:diene_flutter_base/widgets/persistent_form.dart';
import 'package:diene_flutter_base/widgets/problem_visualizer.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

final class _IdleAuthGateway implements AuthGateway {
  @override
  Future<SessionTokens> signIn() => throw UnimplementedError();

  @override
  Future<SessionTokens> refresh(SessionTokens current) =>
      throw UnimplementedError();

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

final class _LifecycleAuthGateway implements AuthGateway {
  int reMints = 0;

  @override
  Future<SessionTokens> signIn() async => _tokens('signed-in');

  @override
  Future<SessionTokens> refresh(SessionTokens current) async =>
      _tokens('refreshed');

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    reMints += 1;
    return _tokens('open-$reMints');
  }

  @override
  Future<void> signOut() async {}

  SessionTokens _tokens(String suffix) {
    final DateTime now = DateTime.now().toUtc();
    return SessionTokens(
      accessToken: 'access-$suffix',
      refreshToken: 'refresh-$suffix',
      refreshFamily: 'lifecycle-family',
      accessExpiresAt: now.add(const Duration(minutes: 10)),
      refreshExpiresAt: now.add(const Duration(days: 14)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocaleSettings.setLocaleRawSync('en');
  });

  testWidgets('AsyncButton disables, shows pending, and avoids double-fire', (
    WidgetTester tester,
  ) async {
    final Completer<void> request = Completer<void>();
    int calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncButton(
            onPressed: () {
              calls += 1;
              return request.future;
            },
            label: const Text('Run request'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run request'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    request.complete();
    await tester.pumpAndSettle();
    expect(find.text('Run request'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'persistent field validates live, restores, and clears its draft',
    (WidgetTester tester) async {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final GlobalKey<PersistentFormFieldState> key =
          GlobalKey<PersistentFormFieldState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersistentFormField(
              key: key,
              storageKey: 'draft.name',
              label: 'Name',
              preferences: preferences,
              validator: (String value) =>
                  value.length < 3 ? 'Too short' : null,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Al');
      await tester.pump();
      expect(find.text('Too short'), findsOneWidget);
      expect(preferences.getString('draft.name'), 'Al');

      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pump();
      expect(find.text('Too short'), findsNothing);
      await key.currentState!.clear();
      await tester.pump();
      expect(preferences.getString('draft.name'), isNull);
      expect(find.text('Alex'), findsNothing);
    },
  );

  testWidgets('bottom-sheet selector and keypad amount input react to taps', (
    WidgetTester tester,
  ) async {
    String locale = 'English';
    int amount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) => Column(
                children: <Widget>[
                  BottomSheetSelector<String>(
                    label: 'Language',
                    value: locale,
                    options: const <SelectorOption<String>>[
                      SelectorOption<String>(
                        value: 'English',
                        label: 'English',
                      ),
                      SelectorOption<String>(
                        value: 'Español',
                        label: 'Español',
                      ),
                    ],
                    onChanged: (String value) => setState(() => locale = value),
                  ),
                  AmountInput(
                    label: 'Budget',
                    help: 'Use the keypad',
                    onChanged: (int value) => setState(() => amount = value),
                  ),
                  Text('minor=$amount'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(find.text('Español'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('minor=12'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('minor=1'), findsOneWidget);
  });

  testWidgets('ProblemVisualizer renders recoverable and fatal tiers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProblemVisualizer(
            problem: Problem(
              type: 'urn:test:retry',
              title: 'Try again',
              status: 503,
              recoverable: true,
            ),
            retryLabel: 'Retry',
            copyLabel: 'Copy',
          ),
        ),
      ),
    );
    expect(find.byType(MaterialBanner), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProblemVisualizer(
            problem: Problem(
              type: 'urn:test:fatal',
              title: 'Fatal problem',
              status: 500,
            ),
            retryLabel: 'Retry',
            copyLabel: 'Copy details',
          ),
        ),
      ),
    );
    expect(find.text('Copy details'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('locale and runtime color changes rebuild the shipped app', (
    WidgetTester tester,
  ) async {
    final _AppHarness harness = await _pumpApp(tester);
    final Color before = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme
        .primary;
    expect(
      find.text('A calm control room for every landscape.'),
      findsOneWidget,
    );

    await tester.runAsync(() => harness.settings.setLocale(const Locale('es')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Una sala de control serena para cada paisaje.'),
      findsOneWidget,
    );

    await harness.settings.setPrimary(const Color(0xFFB91C1C));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final Color after = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme
        .primary;
    expect(after, isNot(before));
  });

  testWidgets('search state is reflected in the routed query parameter', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pump();

    final Finder input = find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(EditableText),
    );
    await tester.enterText(input, 'incident 42');
    await tester.pump();

    final BuildContext context = tester.element(find.byType(SearchBar));
    expect(GoRouterState.of(context).uri.queryParameters['q'], 'incident 42');
  });

  testWidgets('an authenticated app re-mints access on open', (
    WidgetTester tester,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final config = testConfig();
    final _LifecycleAuthGateway gateway = _LifecycleAuthGateway();
    final SessionController session = SessionController(
      gateway: gateway,
      onboarding: OnboardingCoordinator(
        homePicker: SingleRegionHomePicker(
          gateway: MemoryHomeClaimGateway(),
          landscape: 'lapras',
        ),
        gateway: DemoOnboardingGateway(),
        backendId: 'primary',
      ),
      accessLifetime: config.session.accessLifetime,
      refreshLifetime: config.session.refreshLifetime,
    );
    await session.signIn();

    await tester.pumpWidget(
      DieneApp(
        config: config,
        settings: AppSettingsController(
          config: config,
          preferences: preferences,
        ),
        session: session,
        preferences: preferences,
      ),
    );
    await tester.pump();

    expect(gateway.reMints, 1);
  });

  for (final String locale in <String>['en', 'es']) {
    testWidgets('shipped home has no layout overflow in $locale', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final _AppHarness harness = await _pumpApp(tester);
      await tester.runAsync(() => harness.settings.setLocale(Locale(locale)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final Object? exception = tester.takeException();
      expect(exception, isNull);
    });
  }
}

final class _AppHarness {
  const _AppHarness(this.settings);

  final AppSettingsController settings;
}

Future<_AppHarness> _pumpApp(WidgetTester tester) async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final config = testConfig();
  final AppSettingsController settings = AppSettingsController(
    config: config,
    preferences: preferences,
  );
  final SessionController session = SessionController(
    gateway: _IdleAuthGateway(),
    onboarding: OnboardingCoordinator(
      homePicker: SingleRegionHomePicker(
        gateway: MemoryHomeClaimGateway(),
        landscape: 'lapras',
      ),
      gateway: DemoOnboardingGateway(),
      backendId: 'primary',
    ),
    accessLifetime: config.session.accessLifetime,
    refreshLifetime: config.session.refreshLifetime,
  );
  await tester.pumpWidget(
    DieneApp(
      config: config,
      settings: settings,
      session: session,
      preferences: preferences,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _AppHarness(settings);
}
