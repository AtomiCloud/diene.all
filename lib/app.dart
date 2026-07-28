import 'dart:async';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/session_controller.dart';
import 'config/app_config.dart';
import 'config/app_settings_controller.dart';
import 'i18n/translations.g.dart';
import 'onboarding/onboarding.dart';
import 'routing/app_router.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/amount_input.dart';
import 'widgets/async_button.dart';
import 'widgets/bottom_sheet_selector.dart';
import 'widgets/problem_visualizer.dart';
import 'widgets/safe_area_shell.dart';

final class DieneApp extends StatefulWidget {
  const DieneApp({
    required this.config,
    required this.settings,
    required this.session,
    required this.preferences,
    super.key,
  });

  final AppConfig config;
  final AppSettingsController settings;
  final SessionController session;
  final SharedPreferences preferences;

  @override
  State<DieneApp> createState() => _DieneAppState();
}

final class _DieneAppState extends State<DieneApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildAppRouter(
    isAuthenticated: () => widget.session.tokens != null,
    loginBuilder: (BuildContext context, String returnTo) =>
        LoginScreen(session: widget.session, returnTo: returnTo),
    // The shell keeps its own root route: `/` is the existing scaffold home and
    // is deliberately NOT a registry screen, so it is mounted alongside rather
    // than through the route map.
    extraRoutes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => HomeScreen(
          config: widget.config,
          settings: widget.settings,
          preferences: widget.preferences,
          query: state.uri.queryParameters['q'] ?? '',
        ),
      ),
    ],
    initialLocation: '/',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _reMintOnOpen();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reMintOnOpen();
    }
  }

  void _reMintOnOpen() {
    if (widget.session.tokens != null) {
      unawaited(widget.session.onAppOpen());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<AppSettingsController>.value(
        value: widget.settings,
      ),
      ChangeNotifierProvider<SessionController>.value(value: widget.session),
    ],
    child: TranslationProvider(
      child: Consumer<AppSettingsController>(
        builder:
            (
              BuildContext context,
              AppSettingsController settings,
              Widget? child,
            ) => MaterialApp.router(
              routerConfig: _router,
              debugShowCheckedModeBanner: false,
              title: widget.config.branding.appName,
              theme: AppTheme.light(widget.config, settings.primary),
              darkTheme: AppTheme.dark(widget.config, settings.primary),
              themeMode: settings.themeMode,
              locale: settings.locale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
            ),
      ),
    ),
  );
}

final class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.config,
    required this.settings,
    required this.preferences,
    required this.query,
    super.key,
  });

  final AppConfig config;
  final AppSettingsController settings;
  final SharedPreferences preferences;
  final String query;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final SessionController session = context.watch<SessionController>();
    return Scaffold(
      body: SafeAreaShell(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              sliver: SliverList.list(
                children: <Widget>[
                  _Header(config: config),
                  const SizedBox(height: 28),
                  _HeroPanel(
                    config: config,
                    session: session,
                    onPreferences: () => _showPreferences(context),
                  ),
                  if (session.problem != null) ...<Widget>[
                    const SizedBox(height: 16),
                    ProblemVisualizer(
                      problem: session.problem!,
                      retryLabel: copy.retryAction,
                      copyLabel: copy.copyErrorAction,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _ReadinessGrid(config: config),
                  const SizedBox(height: 20),
                  _SignalSearch(query: query),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const SizedBox.square(
                              dimension: 48,
                              child: Icon(Icons.inbox_outlined),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  copy.emptyTitle,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(copy.emptyBody),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPreferences(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (BuildContext context) =>
            _PreferencesSheet(settings: settings, preferences: preferences),
      );
}

final class _Header extends StatelessWidget {
  const _Header({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SvgPicture.asset(
            config.branding.logoAsset,
            height: 48,
            semanticsLabel: config.branding.appName,
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                config.identity.landscape.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

final class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.config,
    required this.session,
    required this.onPreferences,
  });

  final AppConfig config;
  final SessionController session;
  final VoidCallback onPreferences;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(config.theme.radius + 8),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            colors.primaryContainer,
            colors.surfaceContainerHighest,
            colors.secondaryContainer.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(config.theme.radius + 8),
        child: Stack(
          children: <Widget>[
            const PositionedDirectional(
              top: -55,
              end: -35,
              child: _SignalRings(),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 330),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.heroEyebrow,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        letterSpacing: 2.4,
                        color: colors.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 570),
                      child: Text(
                        copy.heroTitle,
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        copy.heroBody,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        AsyncButton(
                          icon: Icons.route_rounded,
                          onPressed:
                              session.status == SessionStatus.authenticating
                              ? null
                              : () async {
                                  final Result<OnboardingPhase> result =
                                      await session.signIn();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  result.match<void>(
                                    ok: (OnboardingPhase _) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            copy.onboardingComplete,
                                          ),
                                        ),
                                      );
                                    },
                                    err: (Problem failure) {},
                                  );
                                },
                          label: Text(copy.startAction),
                        ),
                        AsyncButton(
                          outlined: true,
                          icon: Icons.tune_rounded,
                          onPressed: () async => onPreferences(),
                          label: Text(copy.secondaryAction),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SignalRings extends StatelessWidget {
  const _SignalRings();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox.square(
      dimension: 230,
      child: CustomPaint(
        painter: _SignalPainter(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
    ),
  );
}

final class _SignalPainter extends CustomPainter {
  const _SignalPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final double inset in <double>[8, 32, 58, 86]) {
      canvas.drawOval(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - (inset * 2),
          size.height - (inset * 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter oldDelegate) => oldDelegate.color != color;
}

final class _SignalSearch extends StatefulWidget {
  const _SignalSearch({required this.query});

  final String query;

  @override
  State<_SignalSearch> createState() => _SignalSearchState();
}

final class _SignalSearchState extends State<_SignalSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(_SignalSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateRoute(String value) {
    final String query = value.trim();
    final Uri route = Uri(
      path: '/',
      queryParameters: query.isEmpty ? null : <String, String>{'q': query},
    );
    context.replace(route.toString());
  }

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              copy.searchLabel,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SearchBar(
              controller: _controller,
              hintText: copy.searchHint,
              leading: const Icon(Icons.search_rounded),
              trailing: <Widget>[
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: copy.clearAction,
                    onPressed: () {
                      _controller.clear();
                      _updateRoute('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (String value) {
                _updateRoute(value);
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            Text(copy.searchState),
          ],
        ),
      ),
    );
  }
}

final class _ReadinessGrid extends StatelessWidget {
  const _ReadinessGrid({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    final List<({IconData icon, String title, String value})> items =
        <({IconData icon, String title, String value})>[
          (
            icon: Icons.layers_outlined,
            title: copy.readinessConfig,
            value: 'base → ${config.identity.landscape} → define',
          ),
          (
            icon: Icons.lock_clock_outlined,
            title: copy.readinessSession,
            value: copy.readinessSessionValue,
          ),
          (
            icon: Icons.translate_rounded,
            title: copy.readinessLocales,
            value: config.locale.supportedLocales.join(' · '),
          ),
          (
            icon: Icons.palette_outlined,
            title: copy.readinessTheme,
            value: config.theme.mode.name,
          ),
        ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool singleColumn = constraints.maxWidth < 620;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: singleColumn
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          item.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(letterSpacing: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.value,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _PreferencesSheet extends StatefulWidget {
  const _PreferencesSheet({required this.settings, required this.preferences});

  final AppSettingsController settings;
  final SharedPreferences preferences;

  @override
  State<_PreferencesSheet> createState() => _PreferencesSheetState();
}

final class _PreferencesSheetState extends State<_PreferencesSheet> {
  int _amount = 0;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.settingsTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(copy.settingsBody),
          const SizedBox(height: 24),
          BottomSheetSelector<ThemeMode>(
            label: copy.themeLabel,
            value: widget.settings.themeMode,
            options: <SelectorOption<ThemeMode>>[
              SelectorOption<ThemeMode>(
                value: ThemeMode.system,
                label: copy.themeSystem,
              ),
              SelectorOption<ThemeMode>(
                value: ThemeMode.light,
                label: copy.themeLight,
              ),
              SelectorOption<ThemeMode>(
                value: ThemeMode.dark,
                label: copy.themeDark,
              ),
            ],
            onChanged: (ThemeMode value) =>
                unawaited(widget.settings.setThemeMode(value)),
          ),
          const SizedBox(height: 12),
          BottomSheetSelector<Locale>(
            label: copy.localeLabel,
            value: widget.settings.locale,
            options: <SelectorOption<Locale>>[
              SelectorOption<Locale>(
                value: const Locale('en'),
                label: copy.localeEnglish,
              ),
              SelectorOption<Locale>(
                value: const Locale('es'),
                label: copy.localeSpanish,
              ),
            ],
            onChanged: (Locale value) {
              unawaited(widget.settings.setLocale(value));
            },
          ),
          const SizedBox(height: 12),
          BottomSheetSelector<Color>(
            label: copy.accentLabel,
            value: widget.settings.primary,
            options: <SelectorOption<Color>>[
              SelectorOption<Color>(
                value: Color(widget.settings.config.theme.primary),
                label: copy.accentIdentity,
              ),
              SelectorOption<Color>(
                value: const Color(0xFF0EA5A8),
                label: copy.accentOcean,
              ),
              SelectorOption<Color>(
                value: const Color(0xFFDB2777),
                label: copy.accentRose,
              ),
              SelectorOption<Color>(
                value: const Color(0xFFD97706),
                label: copy.accentAmber,
              ),
            ],
            onChanged: (Color value) {
              unawaited(widget.settings.setPrimary(value));
            },
          ),
          const SizedBox(height: 24),
          AmountInput(
            label: copy.amountLabel,
            help: copy.amountHelp,
            initialMinorUnits: _amount,
            onChanged: (int value) => setState(() => _amount = value),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _amount = 0),
                  child: Text(copy.clearAction),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    await widget.preferences.setInt(
                      'draft.signalBudget',
                      _amount,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(copy.saveAction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
