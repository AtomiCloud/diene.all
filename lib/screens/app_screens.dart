/// The shipped screens, declared as registry entries.
///
/// Each destination appears exactly once in [appScreens], keyed by a route id
/// from the deeplink route map, and `lib/routing/app_router.dart` BUILDS the
/// `GoRouter` from this list. That is what makes route-for-every-screen a real
/// check: there is no second place a screen could be reached from.
///
/// Every screen follows the screen standard — a stable route, explicit
/// loading/empty/error states where it has them, `SafeAreaShell`, a back path
/// where it is not the root, logical directional padding, and route parsing done
/// at the edge (in the builder) rather than inside the render tree.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../i18n/translations.g.dart';
import '../routing/query_state.dart';
import '../routing/route_map.dart';
import '../widgets/async_button.dart';
import '../widgets/safe_area_shell.dart';
import 'screen_registry.dart';
import 'signal_search_bar.dart';

/// The shipped registry. The route-for-every-screen gate asserts every entry's
/// [ScreenDefinition.routeId] resolves in `deeplinkRoutes`, and that the set of
/// declared ids is a SUBSET of the map's ids.
final List<ScreenDefinition> appScreens = <ScreenDefinition>[
  ScreenDefinition(
    routeId: ScreenIds.home,
    title: 'Home',
    builder: (BuildContext context, ScreenRouteContext route) =>
        SignalHomeScreen(
          // Route parsing at the edge: the screen below receives a parsed
          // record, never a GoRouterState.
          query: SignalQuery.fromQueryParameters(route.queryParameters),
        ),
  ),
  ScreenDefinition(
    routeId: ScreenIds.onboarding,
    title: 'Onboarding',
    builder: (BuildContext context, ScreenRouteContext route) =>
        const OnboardingScreen(),
  ),
  ScreenDefinition(
    routeId: ScreenIds.finish,
    title: 'Finish onboarding',
    protected: true,
    builder: (BuildContext context, ScreenRouteContext route) =>
        const OnboardingFinishScreen(),
  ),
  ScreenDefinition(
    routeId: ScreenIds.profile,
    title: 'Profile',
    protected: true,
    builder: (BuildContext context, ScreenRouteContext route) =>
        ProfileScreen(tab: route.queryParameters['tab'] ?? 'overview'),
  ),
  ScreenDefinition(
    routeId: ScreenIds.settings,
    title: 'Settings',
    protected: true,
    builder: (BuildContext context, ScreenRouteContext route) => SettingsScreen(
      query: SignalQuery.fromQueryParameters(route.queryParameters),
    ),
  ),
];

/// The app path for a screen id. Throws when the id is unmapped — a dead
/// navigation target should fail loudly at the call site, not silently route to
/// the wrong place.
String pathForScreen(String routeId) {
  final DeeplinkRoute? route = routeById(routeId);
  if (route == null) {
    throw StateError(
      'screen "$routeId" has no route-map entry; add one to deeplinkRoutes',
    );
  }
  return route.app;
}

/// The signal list — the url-as-state screen. Its whole filter state lives in
/// the route, so the link in the address bar reproduces what the viewer sees.
final class SignalHomeScreen extends StatelessWidget {
  const SignalHomeScreen({required this.query, super.key});

  final SignalQuery query;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(copy.searchLabel)),
      body: SafeAreaShell(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: <Widget>[
            SignalSearchBar(
              query: query,
              path: pathForScreen(ScreenIds.home),
              hintText: copy.searchHint,
              clearTooltip: copy.clearAction,
            ),
            const SizedBox(height: 12),
            Text(copy.searchState),
            const SizedBox(height: 20),
            _FilterChips(query: query),
            const SizedBox(height: 20),
            // The empty state is designed, not forgotten (screen standard).
            if (query.text.isEmpty && query.severities.isEmpty)
              _EmptyPanel(title: copy.emptyTitle, body: copy.emptyBody)
            else
              _ResultPanel(query: query),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                AsyncButton(
                  icon: Icons.person_outline_rounded,
                  outlined: true,
                  // Async trigger: AsyncButton disables and shows a spinner, so
                  // there is no dead tap while navigation resolves.
                  onPressed: () async =>
                      context.go(pathForScreen(ScreenIds.profile)),
                  label: Text(copy.readinessSession),
                ),
                AsyncButton(
                  icon: Icons.tune_rounded,
                  outlined: true,
                  onPressed: () async =>
                      context.go(pathForScreen(ScreenIds.settings)),
                  label: Text(copy.settingsTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Severity filters, each writing itself into the route.
final class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.query});

  final SignalQuery query;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final SignalSeverity severity in SignalSeverity.values)
        FilterChip(
          label: Text(severity.wire),
          selected: query.severities.contains(severity),
          onSelected: (bool selected) {
            final List<SignalSeverity> next = <SignalSeverity>[
              ...query.severities,
            ];
            if (selected) {
              next.add(severity);
            } else {
              next.remove(severity);
            }
            // A filter change is a new view worth a history entry, so `go`
            // rather than `replace` — Back returns to the previous filter set.
            context.go(
              query
                  .copyWith(severities: next, page: 1)
                  .toLocation(pathForScreen(ScreenIds.home)),
            );
          },
        ),
    ],
  );
}

final class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(body),
        ],
      ),
    ),
  );
}

/// Renders the parsed state back to the viewer. This is what makes the
/// restoration claim observable: the panel reads only from [SignalQuery], so if
/// the route round trip lost a filter the screen shows it lost.
final class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.query});

  final SignalQuery query;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('text=${query.text}', key: const ValueKey<String>('state.text')),
          Text(
            'severities=${query.severities.map((SignalSeverity s) => s.wire).join(',')}',
            key: const ValueKey<String>('state.severities'),
          ),
          Text(
            'landscape=${query.landscape ?? '-'}',
            key: const ValueKey<String>('state.landscape'),
          ),
          Text(
            'sort=${query.sort.wire}',
            key: const ValueKey<String>('state.sort'),
          ),
          Text('page=${query.page}', key: const ValueKey<String>('state.page')),
          Text(
            'unresolvedOnly=${query.unresolvedOnly}',
            key: const ValueKey<String>('state.unresolved'),
          ),
        ],
      ),
    ),
  );
}

/// The onboarding entry point — reachable unauthenticated, by design.
final class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(copy.heroEyebrow)),
      body: SafeAreaShell(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: <Widget>[
            Text(
              copy.heroTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(copy.heroBody),
            const SizedBox(height: 24),
            AsyncButton(
              icon: Icons.arrow_forward_rounded,
              onPressed: () async =>
                  context.go(pathForScreen(ScreenIds.finish)),
              label: Text(copy.startAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// The protected tail of onboarding.
final class OnboardingFinishScreen extends StatelessWidget {
  const OnboardingFinishScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(copy.statusReady)),
      body: SafeAreaShell(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: <Widget>[
            Text(copy.onboardingComplete),
            const SizedBox(height: 20),
            AsyncButton(
              icon: Icons.home_rounded,
              outlined: true,
              onPressed: () async => context.go(pathForScreen(ScreenIds.home)),
              label: Text(copy.searchLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// A protected screen whose sub-view is query state, so a deeplink into a
/// specific tab survives login.
final class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.tab, super.key});

  final String tab;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(copy.readinessSession)),
      body: SafeAreaShell(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: <Widget>[
            Text(copy.readinessSessionValue),
            const SizedBox(height: 12),
            Text('tab=$tab', key: const ValueKey<String>('profile.tab')),
          ],
        ),
      ),
    );
  }
}

/// A protected screen that also carries query state.
final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.query, super.key});

  final SignalQuery query;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(copy.settingsTitle)),
      body: SafeAreaShell(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: <Widget>[
            Text(copy.settingsBody),
            const SizedBox(height: 16),
            _ResultPanel(query: query),
          ],
        ),
      ),
    );
  }
}
