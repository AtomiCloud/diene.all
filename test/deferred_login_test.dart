import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart' as engine;
import 'package:diene_flutter_base/auth/deferred_login.dart';
import 'package:diene_flutter_base/auth/session_controller.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A 43-character base64url nonce, the exact shape C0 §7 mandates.
const String _nonce = 'wS3Xv7Qk1Lm9Zt0Ab2Cd4Ef6Gh8Ij0Kl2Mn4Op6Qr8x';
const String _carrier = '$appHandoffCarrierPrefix$_nonce';

final class _FakeCarrierSource implements CarrierSource {
  _FakeCarrierSource(this.channel, this.raw);

  @override
  final CarrierChannel channel;
  String? raw;
  int reads = 0;
  final List<String> processed = <String>[];

  @override
  Future<String?> readCarrier() async {
    reads += 1;
    return raw;
  }

  @override
  Future<void> markProcessed(String value) async {
    processed.add(value);
    if (raw == value) {
      raw = null;
    }
  }
}

final class _RecordingSignIn implements AuthProvider {
  _RecordingSignIn(this.now, {this.throws = false});

  final DateTime now;
  final bool throws;
  final List<Map<String, String>> calls = <Map<String, String>>[];

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async {
    calls.add(extraParams);
    if (throws) {
      throw StateError('hosted sign-in failed');
    }
    return SessionTokens(
      accessToken: 'access-handoff',
      refreshToken: 'refresh-handoff',
      refreshFamily: 'handoff-family',
      accessExpiresAt: now.add(const Duration(minutes: 10)),
      refreshExpiresAt: now.add(const Duration(days: 14)),
    );
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) =>
      throw UnsupportedError('unused by deferred-login tests');

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) =>
      throw UnsupportedError('unused by deferred-login tests');

  @override
  Future<void> signOut() async {}

  @override
  Future<engine.ResourceToken> resourceToken(engine.ResourceKey key) =>
      throw UnsupportedError('unused by deferred-login tests');

  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> freshClaimToken() async => null;
}

final class _RedeemLog {
  int calls = 0;
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  final List<Uri> uris = <Uri>[];
}

/// Mocked HTTP — no real backend is contacted anywhere in this suite.
AppHandoffRedeemClient _redeemClient(
  _RedeemLog log, {
  int status = 200,
  String? body,
}) {
  final http.Client client = MockClient((http.Request request) async {
    log.calls += 1;
    log.uris.add(request.url);
    log.bodies.add(jsonDecode(request.body) as Map<String, Object?>);
    if (status != 200) {
      return http.Response(
        jsonEncode(<String, Object?>{
          'type': 'https://example.invalid/$appHandoffExpiredWireId',
          'title': 'App handoff expired',
          'status': status,
        }),
        status,
      );
    }
    return http.Response(
      body ??
          jsonEncode(<String, Object?>{
            'token': 'one-time-token',
            'email': 'user@example.invalid',
            'expiresIn': 120,
          }),
      200,
    );
  });
  return AppHandoffRedeemClient(
    mount: Uri.parse('https://api.example.invalid/app-handoff'),
    httpClient: client,
  );
}

DeferredLoginReceiver _receiver({
  required List<CarrierSource> sources,
  required NonceLedger ledger,
  required AppHandoffRedeemClient redeem,
  required AuthProvider signIn,
  required DateTime now,
}) => DeferredLoginReceiver(
  sources: sources,
  ledger: ledger,
  redeemClient: redeem,
  signIn: signIn,
  device: const HandoffDevice(platform: 'android', appVersion: '1.0.0'),
  now: () => now,
);

void main() {
  final DateTime now = DateTime.utc(2026, 7, 27, 9);

  group('carrier parsing', () {
    const CarrierParser parser = CarrierParser();

    test('clipboard carrier is the canonical text, whitespace trimmed', () {
      expect(parser.parse('  $_carrier  ', CarrierChannel.clipboard), _nonce);
    });

    test('install referrer carries one percent-encoded app_handoff field', () {
      final String referrer =
          'utm_source=web&app_handoff=${Uri.encodeQueryComponent(_carrier)}'
          '&utm_campaign=launch';
      expect(parser.parse(referrer, CarrierChannel.installReferrer), _nonce);
    });

    test('duplicate app_handoff fields are treated as absent', () {
      final String encoded = Uri.encodeQueryComponent(_carrier);
      expect(
        parser.parse(
          'app_handoff=$encoded&app_handoff=$encoded',
          CarrierChannel.installReferrer,
        ),
        isNull,
      );
    });

    test('a nonce of the wrong length is rejected', () {
      expect(
        parser.parse(
          '${appHandoffCarrierPrefix}too-short',
          CarrierChannel.clipboard,
        ),
        isNull,
      );
    });

    test('a carrier without the v1 prefix is rejected', () {
      expect(parser.parse(_nonce, CarrierChannel.clipboard), isNull);
    });
  });

  test('redeem posts to {mount}/redeem with no doubled segment', () async {
    final _RedeemLog log = _RedeemLog();
    final AppHandoffRedeemClient client = _redeemClient(log);

    final Result<RedeemedHandoff> result = await client.redeem(
      nonce: _nonce,
      device: const HandoffDevice(platform: 'ios', model: 'iPhone'),
    );

    expect(result.isOk, isTrue);
    expect(
      log.uris.single.toString(),
      'https://api.example.invalid/app-handoff/redeem',
    );
    expect(log.bodies.single['nonce'], _nonce);
    expect(
      (log.bodies.single['device']! as Map<String, Object?>)['platform'],
      'ios',
    );
    final RedeemedHandoff handoff = (result as Ok<RedeemedHandoff>).value;
    expect(handoff.token, 'one-time-token');
    expect(handoff.email, 'user@example.invalid');
    expect(handoff.expiresIn, 120);
  });

  test('mocked redeem then signIn(extraParams:) completes the login', () async {
    final _RedeemLog log = _RedeemLog();
    final _FakeCarrierSource source = _FakeCarrierSource(
      CarrierChannel.installReferrer,
      'app_handoff=${Uri.encodeQueryComponent(_carrier)}',
    );
    final _RecordingSignIn signIn = _RecordingSignIn(now);
    final DeferredLoginReceiver receiver = _receiver(
      sources: <CarrierSource>[source],
      ledger: NonceLedger(store: MemoryNonceLedgerStore()),
      redeem: _redeemClient(log),
      signIn: signIn,
      now: now,
    );

    final DeferredLoginReport report = await receiver.attempt();

    expect(report.outcome, DeferredLoginOutcome.signedIn);
    expect(report.email, 'user@example.invalid');
    expect(report.tokens!.accessToken, 'access-handoff');
    expect(log.calls, 1);
    expect(signIn.calls.single, <String, String>{
      'one_time_token': 'one-time-token',
      'login_hint': 'user@example.invalid',
    });
    // The carrier is cleared BEFORE redeem (C0 §7).
    expect(
      report.steps,
      containsAllInOrder(<String>['carrier-cleared', 'redeemed', 'signed-in']),
    );
    expect(source.processed, hasLength(1));
  });

  test('an expired nonce is never redeemed', () async {
    final MemoryNonceLedgerStore store = MemoryNonceLedgerStore();
    // The carrier was first seen 16 minutes ago; the TTL is 15.
    await NonceLedger(
      store: store,
    ).claim(_nonce, now.subtract(const Duration(minutes: 16)));
    final _RedeemLog log = _RedeemLog();
    final _RecordingSignIn signIn = _RecordingSignIn(now);
    final DeferredLoginReceiver receiver = _receiver(
      sources: <CarrierSource>[
        _FakeCarrierSource(CarrierChannel.clipboard, _carrier),
      ],
      ledger: NonceLedger(store: store),
      redeem: _redeemClient(log),
      signIn: signIn,
      now: now,
    );

    final DeferredLoginReport report = await receiver.attempt();

    expect(report.outcome, DeferredLoginOutcome.interactiveFallback);
    expect(report.fallbackReason, 'expired');
    expect(log.calls, 0, reason: 'an expired nonce must not reach the wire');
    expect(signIn.calls, isEmpty);
  });

  test('the TTL boundary is inclusive at exactly 15 minutes', () async {
    final MemoryNonceLedgerStore store = MemoryNonceLedgerStore();
    final NonceLedger ledger = NonceLedger(store: store);
    await ledger.claim(_nonce, now.subtract(appHandoffNonceTtl));

    expect(await ledger.claim(_nonce, now), NonceClaim.fresh);
    expect(
      await ledger.claim(_nonce, now.add(const Duration(milliseconds: 1))),
      NonceClaim.expired,
    );
  });

  test('a replayed nonce is rejected on the second launch', () async {
    final MemoryNonceLedgerStore store = MemoryNonceLedgerStore();
    final _RedeemLog log = _RedeemLog();
    final AppHandoffRedeemClient redeem = _redeemClient(log);

    final _FakeCarrierSource first = _FakeCarrierSource(
      CarrierChannel.clipboard,
      _carrier,
    );
    final DeferredLoginReport initial = await _receiver(
      sources: <CarrierSource>[first],
      ledger: NonceLedger(store: store),
      redeem: redeem,
      signIn: _RecordingSignIn(now),
      now: now,
    ).attempt();
    expect(initial.outcome, DeferredLoginOutcome.signedIn);
    expect(log.calls, 1);

    // A second launch finds the same carrier still on the clipboard.
    final _RecordingSignIn replaySignIn = _RecordingSignIn(now);
    final DeferredLoginReport replay = await _receiver(
      sources: <CarrierSource>[
        _FakeCarrierSource(CarrierChannel.clipboard, _carrier),
      ],
      ledger: NonceLedger(store: store),
      redeem: redeem,
      signIn: replaySignIn,
      now: now.add(const Duration(minutes: 1)),
    ).attempt();

    expect(replay.outcome, DeferredLoginOutcome.interactiveFallback);
    expect(replay.fallbackReason, 'alreadyUsed');
    expect(log.calls, 1, reason: 'the replay must not reach the wire twice');
    expect(replaySignIn.calls, isEmpty);
  });

  test('the ledger persists a fingerprint, never the nonce', () async {
    final MemoryNonceLedgerStore store = MemoryNonceLedgerStore();
    await NonceLedger(store: store).claim(_nonce, now);

    expect(store.records, hasLength(1));
    expect(store.records.keys.single, isNot(contains(_nonce)));
    expect(store.records.keys.single, hasLength(16));
    expect(NonceLedger.fingerprint(_nonce), store.records.keys.single);
  });

  test('a 410 from redeem falls back to interactive login', () async {
    final _RedeemLog log = _RedeemLog();
    final _RecordingSignIn signIn = _RecordingSignIn(now);
    final DeferredLoginReport report = await _receiver(
      sources: <CarrierSource>[
        _FakeCarrierSource(CarrierChannel.clipboard, _carrier),
      ],
      ledger: NonceLedger(store: MemoryNonceLedgerStore()),
      redeem: _redeemClient(log, status: 410),
      signIn: signIn,
      now: now,
    ).attempt();

    expect(report.outcome, DeferredLoginOutcome.interactiveFallback);
    expect(report.fallbackReason, 'urn:diene:problem:$appHandoffExpiredWireId');
    expect(log.calls, 1);
    expect(signIn.calls, isEmpty);
  });

  test('no carrier at all falls back without touching the wire', () async {
    final _RedeemLog log = _RedeemLog();
    final DeferredLoginReport report = await _receiver(
      sources: <CarrierSource>[
        _FakeCarrierSource(CarrierChannel.installReferrer, 'utm_source=web'),
        _FakeCarrierSource(CarrierChannel.clipboard, null),
      ],
      ledger: NonceLedger(store: MemoryNonceLedgerStore()),
      redeem: _redeemClient(log),
      signIn: _RecordingSignIn(now),
      now: now,
    ).attempt();

    expect(report.outcome, DeferredLoginOutcome.interactiveFallback);
    expect(report.fallbackReason, 'no-carrier');
    expect(log.calls, 0);
  });

  test('a failed hosted sign-in falls back and burns the nonce', () async {
    final MemoryNonceLedgerStore store = MemoryNonceLedgerStore();
    final _RedeemLog log = _RedeemLog();
    final DeferredLoginReport report = await _receiver(
      sources: <CarrierSource>[
        _FakeCarrierSource(CarrierChannel.clipboard, _carrier),
      ],
      ledger: NonceLedger(store: store),
      redeem: _redeemClient(log),
      signIn: _RecordingSignIn(now, throws: true),
      now: now,
    ).attempt();

    expect(report.outcome, DeferredLoginOutcome.interactiveFallback);
    expect(
      await NonceLedger(store: store).claim(_nonce, now),
      NonceClaim.alreadyUsed,
      reason: 'a consumed one-time token must never be retried',
    );
  });
}
