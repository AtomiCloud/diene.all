/// Shared deferred-login (app-handoff) fixture — mounted onto a [StubServer].
///
/// This is how `diene_e2e` CONSUMES the one C0 app-handoff contract fixture
/// without building a second bespoke server: [AppHandoffStub] is a canonical
/// fake of the mint/redeem behaviour (C0 §7 lifecycle, single-use nonce,
/// generic-expiry no-oracle failure) that a journey registers on the generic
/// [StubServer] it already runs. There is deliberately no dedicated
/// app-handoff HTTP server type here.
library;

import 'dart:math';

import '../app_handoff/carrier.dart';
import '../app_handoff/wire.dart';
import 'stub_server.dart';

/// Nonce lifecycle states (C0 §7): `active → claimed → consumed|revoked`.
enum AppHandoffNonceState { active, claimed, consumed, revoked }

class _NonceRecord {
  _NonceRecord({required this.sub, required this.email, required this.expiresAt});

  final String sub;
  final String email;
  final DateTime expiresAt;
  AppHandoffNonceState state = AppHandoffNonceState.active;
}

/// A fake identity the redeem-time `GET /api/users/{sub}` check reads (C0 §7).
class AppHandoffUser {
  const AppHandoffUser({
    required this.sub,
    required this.primaryEmail,
    this.isSuspended = false,
    this.deleted = false,
  });

  final String sub;
  final String? primaryEmail;
  final bool isSuspended;

  /// When `true` the redeem-time lookup behaves like a Logto `404`.
  final bool deleted;
}

/// Mountable canonical app-handoff fixture. Construct it, register a directory
/// of known users, [mount] it on a running [StubServer], then drive mint and
/// redeem through the server's [StubServer.baseUrl].
///
/// The fixture enforces the contract that matters for consumer journeys: a
/// nonce is single-use, and every redeem failure — missing, expired, replayed,
/// deleted, suspended, or email-rebound — returns the identical
/// `AppHandoffExpired` (410) body with no distinguishing detail.
class AppHandoffStub {
  AppHandoffStub({
    required this.problemTypeUri,
    this.mountPath = appHandoffDefaultMount,
    this.nonceTtl = const Duration(minutes: 15),
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The `type` URI for the `AppHandoffExpired` problem, built by C0 §2 in the
  /// owning service and injected here so the fixture never re-implements §2.
  final String problemTypeUri;

  /// Configured mount base path; the mint route is `POST {mountPath}` and the
  /// redeem route is `POST {mountPath}/redeem`.
  final String mountPath;

  /// Nonce time-to-live (C0 §7 fixes this at 15 minutes).
  final Duration nonceTtl;

  final Random _random;
  final Map<String, _NonceRecord> _nonces = <String, _NonceRecord>{};
  final Map<String, AppHandoffUser> _users = <String, AppHandoffUser>{};

  /// The identity a fresh mint is attributed to. A journey sets this before
  /// calling mint (the real server reads it from the authenticated session).
  AppHandoffUser? mintingUser;

  /// Registers [user] in the fixture's directory, keyed by its `sub`.
  void addUser(AppHandoffUser user) => _users[user.sub] = user;

  /// The generic no-oracle failure body used for every redeem failure.
  Map<String, Object?> get expiredBody =>
      AppHandoffExpired.withType(problemTypeUri).toJson();

  /// Registers the mint and redeem routes on [server]. [now] supplies the
  /// clock so tests can drive expiry deterministically.
  void mount(StubServer server, {DateTime Function()? now}) {
    final DateTime Function() clock = now ?? DateTime.now;
    server.on('POST', mountPath, (StubRequest request) => _mint(clock));
    server.on(
      'POST',
      '$mountPath/$appHandoffRedeemPath',
      (StubRequest request) => _redeem(request, clock),
    );
  }

  StubResponse _mint(DateTime Function() clock) {
    final AppHandoffUser? user = mintingUser;
    if (user == null) {
      throw StateError('AppHandoffStub.mintingUser must be set before mint');
    }
    final String nonce = _newNonce();
    final DateTime expiresAt = clock().toUtc().add(nonceTtl);
    _nonces[nonce] = _NonceRecord(
      sub: user.sub,
      email: user.primaryEmail ?? '',
      expiresAt: expiresAt,
    );
    return StubResponse.json(
      AppHandoffMint(nonce: nonce, expiresAt: expiresAt.toIso8601String()).toJson(),
    );
  }

  StubResponse _redeem(StubRequest request, DateTime Function() clock) {
    final StubResponse expired = StubResponse.json(expiredBody, status: 410);

    final Map<String, Object?> json;
    try {
      json = request.jsonBody();
    } on FormatException {
      return expired;
    }
    final Object? rawNonce = json['nonce'];
    if (rawNonce is! String) return expired;

    final _NonceRecord? record = _nonces[rawNonce];
    // Atomically claim exactly one unexpired active nonce; anything else is
    // indistinguishable from expiry.
    if (record == null ||
        record.state != AppHandoffNonceState.active ||
        !clock().toUtc().isBefore(record.expiresAt)) {
      return expired;
    }
    record.state = AppHandoffNonceState.claimed;

    // Exactly one redeem-time identity read (C0 §7).
    final AppHandoffUser? user = _users[record.sub];
    final bool ok = user != null &&
        !user.deleted &&
        !user.isSuspended &&
        user.primaryEmail != null &&
        user.primaryEmail!.toLowerCase() == record.email.toLowerCase();
    if (!ok) {
      record.state = AppHandoffNonceState.revoked;
      return expired;
    }

    record.state = AppHandoffNonceState.consumed;
    return StubResponse.json(
      AppHandoffRedeemResponse(
        token: 'ott_${_newNonce()}',
        email: user.primaryEmail!,
      ).toJson(),
    );
  }

  String _newNonce() {
    const String alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return String.fromCharCodes(
      List<int>.generate(
        appHandoffNonceLength,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }
}
