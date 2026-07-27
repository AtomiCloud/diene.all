import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter/foundation.dart';

import '../tokens/session_tokens.dart';
import '../tokens/token_lifetimes.dart';
import 'auth_provider.dart';

/// Coarse session state for UI gating.
enum SessionStatus { unauthenticated, authenticating, authenticated, failed }

/// Owns the token lifecycle for one Logto session (C0 §12):
/// access = 10 minutes, refresh = 14 days rotating with reuse detection, and a
/// silent re-mint on every app open. Lifetimes are ENFORCED, not trusted: a
/// provider that hands back a longer-lived token is rejected.
final class SessionController extends ChangeNotifier {
  SessionController({
    required this._provider,
    this._accessLifetime = TokenLifetimes.access,
    this._refreshLifetime = TokenLifetimes.refresh,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AuthProvider _provider;
  final Duration _accessLifetime;
  final Duration _refreshLifetime;
  final DateTime Function() _now;

  SessionTokens? _tokens;
  SessionStatus _status = SessionStatus.unauthenticated;
  Problem? _problem;

  SessionStatus get status => _status;
  Problem? get problem => _problem;
  SessionTokens? get tokens => _tokens;

  /// Interactive sign-in. [extraParams] carries deferred-login one-time-token /
  /// login-hint params when redeeming an app-handoff carrier.
  Future<Result<SessionTokens>> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async {
    _status = SessionStatus.authenticating;
    _problem = null;
    notifyListeners();
    try {
      final SessionTokens issued = await _provider.signIn(
        extraParams: extraParams,
      );
      _validateLifetime(issued);
      _tokens = issued;
      _status = SessionStatus.authenticated;
      notifyListeners();
      return Ok<SessionTokens>(issued);
    } on Object catch (error) {
      return _fail(
        type: 'urn:diene:problem:auth',
        title: 'Sign-in failed',
        detail: error.toString(),
      );
    }
  }

  /// Rotating refresh with reuse detection. A refresh that changes the family
  /// or re-returns the same refresh token signs the session out (theft).
  Future<Result<SessionTokens>> refresh() async {
    final SessionTokens? current = _tokens;
    if (current == null || !current.refreshValidAt(_now())) {
      return const Err<SessionTokens>(
        Problem(
          type: 'urn:diene:problem:refresh-expired',
          title: 'Refresh expired',
          status: 401,
        ),
      );
    }
    try {
      final SessionTokens next = await _provider.refresh(current);
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

  /// Silent re-mint on app open: a fresh session always starts on a fresh
  /// access token (C0 §12). The refresh token is preserved.
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
    if (!current.refreshValidAt(_now())) {
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
      final SessionTokens next = await _provider.reMintOnOpen(current);
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

  /// Clears local + provider session state.
  Future<void> signOut() async {
    _tokens = null;
    _status = SessionStatus.unauthenticated;
    _problem = null;
    notifyListeners();
    await _provider.signOut();
  }

  Result<SessionTokens> _fail({
    required String type,
    required String title,
    String? detail,
  }) {
    final Problem problem = Problem(
      type: type,
      title: title,
      status: 401,
      detail: detail,
      recoverable: true,
    );
    _status = SessionStatus.failed;
    _problem = problem;
    notifyListeners();
    return Err<SessionTokens>(problem);
  }

  void _validateLifetime(SessionTokens value) {
    final DateTime now = _now().toUtc();
    final Duration access = value.accessExpiresAt.difference(now);
    final Duration refresh = value.refreshExpiresAt.difference(now);
    if (access > _accessLifetime || access <= Duration.zero) {
      throw StateError(
        'Access token lifetime must be at most $_accessLifetime',
      );
    }
    if (refresh > _refreshLifetime || refresh <= Duration.zero) {
      throw StateError(
        'Refresh token lifetime must be at most $_refreshLifetime',
      );
    }
  }
}
