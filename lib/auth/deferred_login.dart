/// Deferred deep-link login — the MOBILE half of the app-handoff pair.
///
/// The web app mints an opaque nonce against dotnet-api's `{mount}` route and
/// ships it to the store as a carrier. This receiver reads that carrier
/// (Android Install Referrer / iOS clipboard), redeems it against
/// `{mount}/redeem`, and completes the OIDC code flow through
/// `signIn(extraParams:)` with the returned one-time token.
///
/// Wire shapes come from C0 §7. Everything here is client-side; dotnet-api owns
/// the mint and redeem endpoints and they are NOT reimplemented here.
library;

import 'dart:convert';

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:http/http.dart' as http;

import 'session_controller.dart';

/// The canonical carrier prefix (C0 §7, carrier v1).
const String appHandoffCarrierPrefix = 'atomi-app-handoff:v1:';

/// The Android Install Referrer field that carries the percent-encoded carrier.
const String appHandoffReferrerField = 'app_handoff';

/// Client-side lifetime of a captured carrier, mirroring the server nonce TTL
/// (C0 §7: fixed 15 minutes). A carrier older than this is never redeemed.
const Duration appHandoffNonceTtl = Duration(minutes: 15);

/// The RFC 9457 wire id every redeem failure collapses to (C0 §7, R-E14).
const String appHandoffExpiredWireId = 'app_handoff_expired';

final RegExp _nonceShape = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Where a carrier came from. Telemetry only — never affects identity.
enum CarrierChannel { installReferrer, clipboard }

/// The device block of a redeem request. Telemetry only (C0 §7).
final class HandoffDevice {
  const HandoffDevice({
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.model,
  });

  /// `android` or `ios`.
  final String platform;
  final String? appVersion;
  final String? osVersion;
  final String? model;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    if (appVersion != null) 'appVersion': appVersion,
    if (osVersion != null) 'osVersion': osVersion,
    if (model != null) 'model': model,
  };
}

/// A syntactically valid carrier that has been read off a device channel.
final class CapturedCarrier {
  const CapturedCarrier({required this.nonce, required this.channel});

  final String nonce;
  final CarrierChannel channel;
}

/// Reads the raw carrier text for one channel and marks it processed.
///
/// Android implementations return the Install Referrer query string; iOS
/// implementations return the clipboard contents.
abstract interface class CarrierSource {
  CarrierChannel get channel;

  Future<String?> readCarrier();

  /// Marks the referrer processed, or clears the clipboard only when it still
  /// equals [raw]. Runs BEFORE redeem (C0 §7).
  Future<void> markProcessed(String raw);
}

/// Parses the two carrier encodings into a nonce.
final class CarrierParser {
  const CarrierParser();

  /// Returns the nonce, or null when the carrier is absent or malformed.
  String? parse(String? raw, CarrierChannel channel) {
    if (raw == null) {
      return null;
    }
    final String canonical = switch (channel) {
      CarrierChannel.clipboard => raw.trim(),
      CarrierChannel.installReferrer => _fromReferrer(raw) ?? '',
    };
    if (!canonical.startsWith(appHandoffCarrierPrefix)) {
      return null;
    }
    final String nonce = canonical.substring(appHandoffCarrierPrefix.length);
    return _nonceShape.hasMatch(nonce) ? nonce : null;
  }

  String? _fromReferrer(String raw) {
    final List<String> values = <String>[];
    for (final String pair in raw.split('&')) {
      final int split = pair.indexOf('=');
      if (split <= 0) {
        continue;
      }
      if (Uri.decodeQueryComponent(pair.substring(0, split)) !=
          appHandoffReferrerField) {
        continue;
      }
      values.add(Uri.decodeQueryComponent(pair.substring(split + 1)));
    }
    // Zero or duplicate `app_handoff` fields are treated as absent (C0 §7).
    return values.length == 1 ? values.single : null;
  }
}

/// Verdict of the client-side one-time/TTL guard.
enum NonceClaim { fresh, expired, alreadyUsed }

/// Persisted state for one carrier fingerprint.
final class NonceRecord {
  const NonceRecord({required this.firstSeenAt, required this.consumed});

  final DateTime firstSeenAt;
  final bool consumed;
}

/// Durable store behind [NonceLedger]. Keys are fingerprints, never nonces.
abstract interface class NonceLedgerStore {
  Future<NonceRecord?> read(String fingerprint);

  Future<void> write(String fingerprint, NonceRecord record);
}

/// In-memory [NonceLedgerStore] for tests and for platforms without storage.
final class MemoryNonceLedgerStore implements NonceLedgerStore {
  final Map<String, NonceRecord> records = <String, NonceRecord>{};

  @override
  Future<NonceRecord?> read(String fingerprint) async => records[fingerprint];

  @override
  Future<void> write(String fingerprint, NonceRecord record) async {
    records[fingerprint] = record;
  }
}

/// Client-side single-use + TTL guard over captured carriers.
///
/// The nonce itself is never persisted (C0 §7) — only a non-reversible
/// fingerprint of it, which is enough to recognise a replay across launches.
final class NonceLedger {
  const NonceLedger({
    required this.store,
    this.ttl = appHandoffNonceTtl,
  });

  final NonceLedgerStore store;
  final Duration ttl;

  /// Fingerprints [nonce] with 64-bit FNV-1a. Not a nonce, not reversible.
  static String fingerprint(String nonce) {
    int hash = 0xcbf29ce484222325;
    for (final int unit in utf8.encode(nonce)) {
      hash = (hash ^ unit) * 0x100000001b3;
      hash &= 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Records first sight of [nonce] and decides whether it may be redeemed.
  Future<NonceClaim> claim(String nonce, DateTime now) async {
    final String key = fingerprint(nonce);
    final NonceRecord? existing = await store.read(key);
    if (existing == null) {
      await store.write(
        key,
        NonceRecord(firstSeenAt: now.toUtc(), consumed: false),
      );
      return NonceClaim.fresh;
    }
    if (existing.consumed) {
      return NonceClaim.alreadyUsed;
    }
    // Bypassing this TTL check is the sabotage the deferred-login gate catches.
    if (now.toUtc().difference(existing.firstSeenAt) > ttl) {
      await store.write(
        key,
        NonceRecord(firstSeenAt: existing.firstSeenAt, consumed: true),
      );
      return NonceClaim.expired;
    }
    return NonceClaim.fresh;
  }

  /// Burns [nonce] so no later launch can redeem it again.
  Future<void> markConsumed(String nonce, DateTime firstSeenAt) => store.write(
    fingerprint(nonce),
    NonceRecord(firstSeenAt: firstSeenAt.toUtc(), consumed: true),
  );
}

/// A successful redeem response (C0 §7).
final class RedeemedHandoff {
  const RedeemedHandoff({
    required this.token,
    required this.email,
    required this.expiresIn,
  });

  final String token;
  final String email;
  final int expiresIn;
}

/// Redeem client for `POST {mount}/redeem`.
///
/// [mount] is the configured base path; the redeem route appends exactly one
/// `/redeem` segment and never a second `app-handoff` segment (C0 §7).
final class AppHandoffRedeemClient {
  const AppHandoffRedeemClient({required this.mount, required this.httpClient});

  final Uri mount;
  final http.Client httpClient;

  Uri get redeemUri =>
      mount.replace(path: '${mount.path.replaceAll(RegExp(r'/+$'), '')}/redeem');

  Future<Result<RedeemedHandoff>> redeem({
    required String nonce,
    required HandoffDevice device,
  }) async {
    try {
      final http.Response response = await httpClient.post(
        redeemUri,
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'nonce': nonce,
          'device': device.toJson(),
        }),
      );
      if (response.statusCode != 200) {
        return Err<RedeemedHandoff>(_expired(response.statusCode));
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        return Err<RedeemedHandoff>(_expired(response.statusCode));
      }
      final Object? token = decoded['token'];
      final Object? email = decoded['email'];
      if (token is! String || token.isEmpty || email is! String) {
        return Err<RedeemedHandoff>(_expired(response.statusCode));
      }
      return Ok<RedeemedHandoff>(
        RedeemedHandoff(
          token: token,
          email: email,
          expiresIn: decoded['expiresIn'] as int? ?? 120,
        ),
      );
    } on Object catch (error) {
      return Err<RedeemedHandoff>(_expired(0, detail: error.toString()));
    }
  }

  Problem _expired(int status, {String? detail}) => Problem(
    type: 'urn:diene:problem:$appHandoffExpiredWireId',
    title: 'App handoff expired',
    status: 410,
    detail: detail ?? 'This app handoff is expired or invalid.',
    recoverable: true,
    data: <String, Object?>{'upstreamStatus': status},
  );
}

/// The `signIn(extraParams:)` seam. Narrow on purpose: the shared
/// [AuthGateway] keeps its parameterless contract.
abstract interface class ExtraParamsSignIn {
  Future<SessionTokens> signInWithExtraParams(Map<String, String> extraParams);
}

/// What the receiver did on this launch.
enum DeferredLoginOutcome { signedIn, interactiveFallback }

/// The receiver's report: outcome, the ordered steps it took, and the tokens
/// when a handoff sign-in actually completed.
final class DeferredLoginReport {
  const DeferredLoginReport({
    required this.outcome,
    required this.steps,
    this.tokens,
    this.email,
    this.fallbackReason,
  });

  final DeferredLoginOutcome outcome;
  final List<String> steps;
  final SessionTokens? tokens;
  final String? email;
  final String? fallbackReason;
}

/// Reads the carrier, redeems it, and signs in with the one-time token.
///
/// Every failure path falls back to normal interactive login; there is no
/// carrier-specific retry loop (C0 §7).
final class DeferredLoginReceiver {
  DeferredLoginReceiver({
    required this.sources,
    required this.ledger,
    required this.redeemClient,
    required this.signIn,
    required this.device,
    this.parser = const CarrierParser(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final List<CarrierSource> sources;
  final NonceLedger ledger;
  final AppHandoffRedeemClient redeemClient;
  final ExtraParamsSignIn signIn;
  final HandoffDevice device;
  final CarrierParser parser;
  final DateTime Function() _now;

  Future<DeferredLoginReport> attempt() async {
    final List<String> steps = <String>[];
    final DateTime now = _now().toUtc();

    for (final CarrierSource source in sources) {
      steps.add('read:${source.channel.name}');
      final String? raw = await source.readCarrier();
      final String? nonce = parser.parse(raw, source.channel);
      if (nonce == null) {
        continue;
      }
      steps.add('captured:${source.channel.name}');

      final NonceClaim claim = await ledger.claim(nonce, now);
      if (claim != NonceClaim.fresh) {
        steps.add('rejected:${claim.name}');
        return DeferredLoginReport(
          outcome: DeferredLoginOutcome.interactiveFallback,
          steps: steps,
          fallbackReason: claim.name,
        );
      }
      steps.add('claimed');

      // Mark the carrier processed BEFORE redeem (C0 §7).
      await source.markProcessed(raw!);
      steps.add('carrier-cleared');

      final Result<RedeemedHandoff> redeemed = await redeemClient.redeem(
        nonce: nonce,
        device: device,
      );
      if (redeemed is Err<RedeemedHandoff>) {
        steps.add('redeem-failed');
        await ledger.markConsumed(nonce, now);
        return DeferredLoginReport(
          outcome: DeferredLoginOutcome.interactiveFallback,
          steps: steps,
          fallbackReason: redeemed.problem.type,
        );
      }
      steps.add('redeemed');

      final RedeemedHandoff handoff = (redeemed as Ok<RedeemedHandoff>)
          .value;
      await ledger.markConsumed(nonce, now);
      try {
        final SessionTokens tokens = await signIn.signInWithExtraParams(
          <String, String>{
            'one_time_token': handoff.token,
            'login_hint': handoff.email,
          },
        );
        steps.add('signed-in');
        return DeferredLoginReport(
          outcome: DeferredLoginOutcome.signedIn,
          steps: steps,
          tokens: tokens,
          email: handoff.email,
        );
      } on Object catch (error) {
        steps.add('sign-in-failed');
        return DeferredLoginReport(
          outcome: DeferredLoginOutcome.interactiveFallback,
          steps: steps,
          fallbackReason: error.toString(),
        );
      }
    }

    steps.add('no-carrier');
    return DeferredLoginReport(
      outcome: DeferredLoginOutcome.interactiveFallback,
      steps: steps,
      fallbackReason: 'no-carrier',
    );
  }
}
