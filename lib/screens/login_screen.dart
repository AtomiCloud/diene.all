/// The login screen — the route-side half of the protected-screen pattern.
///
/// This screen owns NO authentication logic. It receives the already-validated
/// [returnTo] location from the router (validated there, so an off-origin value
/// never reaches this widget) and, once the session controller reports success,
/// navigates to it. Sign-in itself belongs to `lib/auth/`.
///
/// The loading state uses a stable shell rather than flashing the protected
/// content behind it (protected-screen standard, Flutter variant).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_controller.dart';
import '../core/result.dart';
import '../i18n/translations.g.dart';
import '../onboarding/onboarding.dart';
import '../routing/deeplink.dart';
import '../widgets/async_button.dart';
import '../widgets/problem_visualizer.dart';
import '../widgets/safe_area_shell.dart';

/// Prompts for sign-in, then continues to the location the viewer asked for.
final class LoginScreen extends StatelessWidget {
  const LoginScreen({required this.session, required this.returnTo, super.key});

  final SessionController session;

  /// Where to go once authenticated. Already validated by the router; re-checked
  /// here so this widget is safe even if a future caller forgets.
  final String returnTo;

  @override
  Widget build(BuildContext context) {
    final Translations copy = context.t;
    final bool pending = session.status == SessionStatus.authenticating;
    return Scaffold(
      appBar: AppBar(title: Text(copy.startAction)),
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
            if (session.problem != null) ...<Widget>[
              const SizedBox(height: 16),
              // A denial is distinct from a sign-in failure: the catalog decides
              // which tier this renders as.
              ProblemVisualizer(
                problem: session.problem!,
                retryLabel: copy.retryAction,
                copyLabel: copy.copyErrorAction,
              ),
            ],
            const SizedBox(height: 24),
            if (pending)
              const Center(
                key: ValueKey<String>('login.pending'),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              AsyncButton(
                icon: Icons.login_rounded,
                // Async trigger with no dead tap: AsyncButton disables and shows
                // a spinner for the whole request.
                onPressed: () async {
                  final Result<OnboardingPhase> result = await session.signIn();
                  if (!context.mounted) {
                    return;
                  }
                  result.fold<void>(
                    // Re-validated at the point of use, so a bad value becomes
                    // the safe default rather than an open redirect.
                    onSuccess: (OnboardingPhase _) =>
                        context.go(continueTo(returnTo)),
                    onFailure: (Problem _) {},
                  );
                },
                label: Text(copy.startAction),
              ),
            const SizedBox(height: 16),
            Text(
              'returnTo=${continueTo(returnTo)}',
              key: const ValueKey<String>('login.returnTo'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
