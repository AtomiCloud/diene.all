import 'package:diene_auth_engine/diene_auth_engine.dart' as diene_auth;
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/foundation.dart';

import '../onboarding/onboarding.dart';

export 'package:diene_auth_engine/diene_auth_engine.dart'
    show SessionStatus, SessionTokens;

/// Compatibility seam for the app's existing providers and test doubles.
///
/// Session lifecycle policy does not live here: [SessionController] adapts
/// every implementation to the published diene_auth_engine controller.
abstract interface class AuthGateway {
  Future<diene_auth.SessionTokens> signIn();
  Future<diene_auth.SessionTokens> refresh(diene_auth.SessionTokens current);
  Future<diene_auth.SessionTokens> reMintOnOpen(
    diene_auth.SessionTokens current,
  );
  Future<void> signOut();
}

/// Compatibility facade over diene_auth_engine's session controller.
///
/// The app-specific onboarding step remains outside the engine. Token
/// issuance, lifetime enforcement, refresh rotation/reuse detection, app-open
/// re-minting, and sign-out are all performed by the published controller.
final class SessionController extends ChangeNotifier {
  SessionController({
    required this.gateway,
    required this.onboarding,
    required this.accessLifetime,
    required this.refreshLifetime,
    DateTime Function()? now,
  }) : _engine = diene_auth.SessionController(
         provider: _AuthProviderFacade(gateway),
         accessLifetime: accessLifetime,
         refreshLifetime: refreshLifetime,
         now: now,
       );

  final AuthGateway gateway;
  final OnboardingCoordinator onboarding;
  final Duration accessLifetime;
  final Duration refreshLifetime;
  final diene_auth.SessionController _engine;

  Problem? _onboardingProblem;

  diene_auth.SessionStatus get status => _onboardingProblem == null
      ? _engine.status
      : diene_auth.SessionStatus.failed;
  Problem? get problem => _onboardingProblem ?? _engine.problem;
  diene_auth.SessionTokens? get tokens => _engine.tokens;

  Future<Result<OnboardingPhase>> signIn() async {
    _onboardingProblem = null;

    // The engine enters `authenticating` synchronously before awaiting the
    // provider. Relay that transition through the compatibility notifier.
    final Future<Result<diene_auth.SessionTokens>> pending = _engine.signIn();
    notifyListeners();
    final Result<diene_auth.SessionTokens> authenticated = await pending;
    if (authenticated is Err<diene_auth.SessionTokens>) {
      notifyListeners();
      return Err<OnboardingPhase>(authenticated.problem);
    }

    try {
      final Result<OnboardingPhase> result = await onboarding.runAfterSignIn();
      if (result is Err<OnboardingPhase>) {
        _onboardingProblem = result.problem;
      }
      notifyListeners();
      return result;
    } on Object catch (error) {
      final Problem problem = Problem(
        type: 'urn:diene:problem:auth',
        title: 'Sign-in failed',
        status: 401,
        detail: error.toString(),
        recoverable: true,
      );
      _onboardingProblem = problem;
      notifyListeners();
      return Err<OnboardingPhase>(problem);
    }
  }

  Future<Result<diene_auth.SessionTokens>> refresh() async {
    final diene_auth.SessionTokens? previousTokens = _engine.tokens;
    final diene_auth.SessionStatus previousStatus = _engine.status;
    final Result<diene_auth.SessionTokens> result = await _engine.refresh();
    _relayEngineChange(previousTokens, previousStatus);
    return result;
  }

  Future<Result<diene_auth.SessionTokens>> onAppOpen() async {
    final diene_auth.SessionTokens? previousTokens = _engine.tokens;
    final diene_auth.SessionStatus previousStatus = _engine.status;
    final Result<diene_auth.SessionTokens> result = await _engine.onAppOpen();
    _relayEngineChange(previousTokens, previousStatus);
    return result;
  }

  Future<void> signOut() async {
    _onboardingProblem = null;
    // The engine clears its state synchronously, before the provider-side
    // sign-out completes, matching the facade's historical notification order.
    final Future<void> pending = _engine.signOut();
    notifyListeners();
    await pending;
  }

  void _relayEngineChange(
    diene_auth.SessionTokens? previousTokens,
    diene_auth.SessionStatus previousStatus,
  ) {
    if (_engine.status == diene_auth.SessionStatus.unauthenticated) {
      _onboardingProblem = null;
    }
    if (!identical(previousTokens, _engine.tokens) ||
        previousStatus != _engine.status) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}

/// Adapts the app's intentionally small compatibility seam to the complete
/// engine provider interface. The extra provider capabilities are not used by
/// diene_auth_engine's session controller and fail closed if that changes.
final class _AuthProviderFacade implements diene_auth.AuthProvider {
  const _AuthProviderFacade(this._gateway);

  final AuthGateway _gateway;

  @override
  Future<diene_auth.SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) {
    if (extraParams.isNotEmpty) {
      throw UnsupportedError(
        'The compatibility AuthGateway does not accept extra sign-in params',
      );
    }
    return _gateway.signIn();
  }

  @override
  Future<diene_auth.SessionTokens> refresh(diene_auth.SessionTokens current) =>
      _gateway.refresh(current);

  @override
  Future<diene_auth.SessionTokens> reMintOnOpen(
    diene_auth.SessionTokens current,
  ) => _gateway.reMintOnOpen(current);

  @override
  Future<void> signOut() => _gateway.signOut();

  @override
  Future<diene_auth.ResourceToken> resourceToken(diene_auth.ResourceKey key) =>
      throw UnsupportedError(
        'Session-only AuthGateway cannot mint ${key.mapKey}',
      );

  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> freshClaimToken() async => null;
}
