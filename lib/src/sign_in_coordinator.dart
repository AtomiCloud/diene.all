import 'auth/session_controller.dart';
import 'contracts/result.dart';
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
/// SIGN-UP only) → OIDC login → per-backend claims-first onboarding → mirror the
/// OnboardSync-written home claim locally → resume the exact returnTo route.
final class SignInCoordinator {
  const SignInCoordinator({
    required SessionController session,
    required HomeClaimResolver homeResolver,
    required MultiBackendOnboarding onboarding,
  }) : _session = session,
       _homeResolver = homeResolver,
       _onboarding = onboarding;

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
    if (homeResult is Failure<HomeResolution>) {
      return Failure<SignInResult>(homeResult.problem);
    }
    HomeResolution home = (homeResult as Success<HomeResolution>).value;

    // 2. OIDC login (carries deferred-login one-time token when present).
    final Result<Object?> login = await _session.signIn(
      extraParams: extraParams,
    );
    if (login is Failure) {
      return Failure<SignInResult>(login.problem);
    }

    // 3. Re-read the AUTHORITATIVE claim from the freshly issued JWT so a
    //    server-changed/removed home_landscape overrides the pre-login value.
    final Result<String?> issued = await _homeResolver.authoritativeHome();
    if (issued is Failure<String?>) {
      return Failure<SignInResult>(issued.problem);
    }
    final String? issuedHome = (issued as Success<String?>).value;
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

    // 5. On the sign-up path, mirror the OnboardSync-written home claim locally.
    if (home.kind == HomeResolutionKind.selected) {
      await _homeResolver.commit(home.landscape);
    }

    // 6. Resume the exact protected route the deeplink targeted.
    final Uri? continueTo = returnTo == null
        ? null
        : ReturnTo.capture(
            returnTo,
          ).match(onSuccess: (_) => returnTo, onFailure: (_) => null);

    return Success<SignInResult>(
      SignInResult(home: home, phases: phases, continueTo: continueTo),
    );
  }
}
