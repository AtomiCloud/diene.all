import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/foundation.dart';

import '../onboarding/onboarding.dart';

final class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshFamily,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String refreshFamily;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
}

abstract interface class AuthGateway {
  Future<SessionTokens> signIn();
  Future<SessionTokens> refresh(SessionTokens current);
  Future<SessionTokens> reMintOnOpen(SessionTokens current);
  Future<void> signOut();
}

enum SessionStatus { unauthenticated, authenticating, authenticated, failed }

final class SessionController extends ChangeNotifier {
  SessionController({
    required this.gateway,
    required this.onboarding,
    required this.accessLifetime,
    required this.refreshLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AuthGateway gateway;
  final OnboardingCoordinator onboarding;
  final Duration accessLifetime;
  final Duration refreshLifetime;
  final DateTime Function() _now;
  SessionTokens? _tokens;
  SessionStatus _status = SessionStatus.unauthenticated;
  Problem? _problem;

  SessionStatus get status => _status;
  Problem? get problem => _problem;
  SessionTokens? get tokens => _tokens;

  Future<Result<OnboardingPhase>> signIn() async {
    _status = SessionStatus.authenticating;
    _problem = null;
    notifyListeners();
    try {
      final SessionTokens issued = await gateway.signIn();
      _validateLifetime(issued);
      _tokens = issued;
      final Result<OnboardingPhase> result = await onboarding.runAfterSignIn();
      if (result is Err<OnboardingPhase>) {
        _status = SessionStatus.failed;
        _problem = result.problem;
      } else {
        _status = SessionStatus.authenticated;
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
      _status = SessionStatus.failed;
      _problem = problem;
      notifyListeners();
      return Err<OnboardingPhase>(problem);
    }
  }

  Future<Result<SessionTokens>> refresh() async {
    final SessionTokens? current = _tokens;
    if (current == null || !current.refreshExpiresAt.isAfter(_now().toUtc())) {
      return const Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:refresh-expired',
          title: 'Refresh expired',
          status: 401,
        ),
      );
    }
    try {
      final SessionTokens next = await gateway.refresh(current);
      if (next.refreshFamily != current.refreshFamily ||
          next.refreshToken == current.refreshToken) {
        await signOut();
        return const Err<SessionTokens>(
          Problem(
            type: 'urn:diene:problem:refresh-reuse',
            title: 'Refresh token reuse detected',
            status: 401,
          ),
        );
      }
      _validateLifetime(next);
      _tokens = next;
      notifyListeners();
      return Ok<SessionTokens>(next);
    } on Object catch (error) {
      return Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:refresh',
          title: 'Session refresh failed',
          status: 401,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }

  Future<Result<SessionTokens>> onAppOpen() async {
    final SessionTokens? current = _tokens;
    if (current == null) {
      return const Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:not-authenticated',
          title: 'Not authenticated',
          status: 401,
        ),
      );
    }
    if (!current.refreshExpiresAt.isAfter(_now().toUtc())) {
      await signOut();
      return const Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:refresh-expired',
          title: 'Refresh expired',
          status: 401,
        ),
      );
    }
    try {
      final SessionTokens next = await gateway.reMintOnOpen(current);
      _validateLifetime(next);
      _tokens = next;
      notifyListeners();
      return Ok<SessionTokens>(next);
    } on Object catch (error) {
      return Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:remint',
          title: 'Could not renew the access token',
          status: 401,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }

  Future<void> signOut() async {
    _tokens = null;
    _status = SessionStatus.unauthenticated;
    _problem = null;
    notifyListeners();
    await gateway.signOut();
  }

  void _validateLifetime(SessionTokens value) {
    final DateTime now = _now().toUtc();
    final Duration access = value.accessExpiresAt.difference(now);
    final Duration refresh = value.refreshExpiresAt.difference(now);
    if (access > accessLifetime || access <= Duration.zero) {
      throw StateError('Access token lifetime must be at most $accessLifetime');
    }
    if (refresh > refreshLifetime || refresh <= Duration.zero) {
      throw StateError(
        'Refresh token lifetime must be at most $refreshLifetime',
      );
    }
  }
}
