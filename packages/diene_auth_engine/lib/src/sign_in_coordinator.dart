import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'auth/session_controller.dart';
import 'home/home_claim.dart';
import 'onboarding/onboarding_phase.dart';
import 'returnto/return_to.dart';

/// The aggregate outcome of a full sign-in.
final class SignInResult {
  const SignInResult({
    required this.home,
    required this.phases,
    this.continueTo,
  });

  /// The resolved home landscape and how it was obtained.
  final HomeResolution home;

  /// Per-backend onboarding phase results (independent per backend).
  final Map<String, Result<OnboardingPhase>> phases;

  /// The exact route to resume after login (returnTo continuation), if any.
  final Uri? continueTo;
}

/// Ties the auth-engine flow together in the C0 §13 order:
/// resolve home claim (present → route home, no Doc B; absent → Doc B selector,
/// SIGN-UP only) → OIDC login → per-backend claims-first onboarding →
/// CONFIRM the OnboardSync-written home claim from a freshly issued JWT (never
/// mirror the Doc B selection as a claim) → resume the exact returnTo route.
final class SignInCoordinator {
  const SignInCoordinator({
    required this._session,
    required this._homeResolver,
    required this._onboarding,
  });

  final SessionController _session;
  final HomeClaimResolver _homeResolver;
  final MultiBackendOnboarding _onboarding;

  /// Runs the full sign-in. [extraParams] carries deferred-login params;
  /// [preferredLandscape] biases the Doc B pick; [returnTo] is the protected
  /// route the deeplink targeted before login.
  Future<Result<SignInResult>> signIn({
    Map<String, String> extraParams = const <String, String>{},
    String? preferredLandscape,
    Uri? returnTo,
  }) async {
    // 1. Resolve the home landscape from the authoritative existing-JWT claim
    //    (C0 §13). A returning user's claim decides the login target; a new
    //    user (claim absent) picks via Doc B. Local cache is never consulted.
    final Result<HomeResolution> homeResult = await _homeResolver.resolve(
      preferred: preferredLandscape,
    );
    if (homeResult is Err<HomeResolution>) {
      return Err<SignInResult>(homeResult.problem);
    }
    HomeResolution home = (homeResult as Ok<HomeResolution>).value;

    // 2. OIDC login (carries deferred-login one-time token when present).
    final Result<Object?> login = await _session.signIn(
      extraParams: extraParams,
    );
    if (login is Err) {
      return Err<SignInResult>(login.problem);
    }

    // 3. Re-read the AUTHORITATIVE claim from the freshly issued JWT so a
    //    server-changed/removed home_landscape overrides the pre-login value.
    final Result<String?> issued = await _homeResolver.authoritativeHome();
    if (issued is Err<String?>) {
      return Err<SignInResult>(issued.problem);
    }
    final String? issuedHome = (issued as Ok<String?>).value;
    if (issuedHome != null) {
      home = HomeResolution(
        landscape: issuedHome,
        kind: HomeResolutionKind.fromClaim,
      );
      await _homeResolver.commit(issuedHome);
    }

    // 4. Per-backend claims-first onboarding (independent per backend).
    final Map<String, Result<OnboardingPhase>> phases = await _onboarding
        .runAll();

    // 5. Sign-up path only: OnboardSync writes the home_landscape claim
    //    server-side during onboarding. The client MUST confirm it from a
    //    freshly issued JWT — the locally selected Doc B landscape is NEVER
    //    persisted as if it were a claim (C0 §13).
    if (home.kind == HomeResolutionKind.selected) {
      // Onboarding must have completed cleanly before a home claim can exist.
      for (final MapEntry<String, Result<OnboardingPhase>> entry
          in phases.entries) {
        final Result<OnboardingPhase> outcome = entry.value;
        if (outcome is Err<OnboardingPhase>) {
          // Do NOT mirror the selection; surface the onboarding failure.
          return Err<SignInResult>(outcome.problem);
        }
      }
      // Confirm the claim from a FORCE-FRESH claim-bearing JWT (never the
      // possibly-stale stored token): the exact token returned by
      // AuthProvider.freshClaimToken is decoded here.
      final Result<String?> confirmed = await _homeResolver.confirmedHome();
      if (confirmed is Err<String?>) {
        return Err<SignInResult>(confirmed.problem);
      }
      final String? confirmedHome = (confirmed as Ok<String?>).value;
      if (confirmedHome == null) {
        // OnboardSync did not surface a home_landscape claim: an explicit
        // unconfirmed state, NOT a mirrored selection.
        return const Err<SignInResult>(
          Problem(
            type: 'urn:diene:problem:home-claim-unconfirmed',
            title: 'Home landscape claim not confirmed after onboarding',
            status: 409,
            recoverable: true,
          ),
        );
      }
      // The confirmed JWT value (which may differ from the selection) is the
      // authoritative home and the only value mirrored.
      home = HomeResolution(
        landscape: confirmedHome,
        kind: HomeResolutionKind.fromClaim,
      );
      await _homeResolver.commit(confirmedHome);
    }

    // 6. Resume the exact protected route the deeplink targeted.
    final Uri? continueTo = returnTo == null
        ? null
        : ReturnTo.capture(
            returnTo,
          ).match(ok: (_) => returnTo, err: (_) => null);

    return Ok<SignInResult>(
      SignInResult(home: home, phases: phases, continueTo: continueTo),
    );
  }
}
