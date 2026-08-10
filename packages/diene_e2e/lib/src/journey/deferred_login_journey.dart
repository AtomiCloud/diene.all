/// Deferred-login journey driver — the client half of the C0 §7 flow.
///
/// Drives the mobile-client steps of app-handoff against an [AppHandoffStub]
/// mounted on a [StubServer]: read the carrier, redeem the nonce, and fall
/// back to interactive login on any `AppHandoffExpired` response. It builds
/// requests and interprets responses through the shared contract models; it
/// owns no server behaviour of its own.
library;

import 'dart:convert';
import 'dart:io';

import '../app_handoff/carrier.dart';
import '../app_handoff/wire.dart';
import '../stub/stub_server.dart';

/// What a deferred-login JOURNEY attempt resolved to.
///
/// NAMED `DeferredLoginJourneyOutcome`, not `DeferredLoginOutcome`, deliberately.
/// `diene_auth_engine` OWNS the client-side deferred-login contract and declares
/// its own `DeferredLoginOutcome` — a `sealed class` with `DeferredLoginReady`
/// (carrying `extraParams` for `signIn(extraParams:)`) and
/// `DeferredLoginFallback` (carrying an optional `Problem`). Because `diene_e2e`
/// re-exports the whole auth-engine barrel as part of the version train, the
/// original name collided outright: the compiler reported
/// "'DeferredLoginOutcome' is imported from both
/// 'package:diene_auth_engine/src/deferred/deferred_login.dart' and
/// 'package:diene_e2e/src/journey/deferred_login_journey.dart'" and the meta
/// suite would not load.
///
/// The rename is the correct fix rather than a `hide`, because these are
/// genuinely DIFFERENT abstractions and neither is a superset of the other:
/// auth-engine's models the PRODUCTION client's decision and carries the data
/// that feeds a real sign-in, while this enum reports what a TEST JOURNEY
/// observed while driving a stub. Hiding the owner's type from the bundle would
/// have removed a production contract from the version train in order to keep a
/// harness name — the wrong direction. The owner keeps the contract name; the
/// harness qualifies its own.
enum DeferredLoginJourneyOutcome {
  /// A valid carrier was redeemed into a one-time token.
  redeemed,

  /// No usable carrier, or the server returned `AppHandoffExpired` — the
  /// client falls back to normal interactive login.
  interactiveFallback,
}

/// The result of driving one deferred-login attempt.
class DeferredLoginResult {
  const DeferredLoginResult({required this.outcome, this.redeem});

  final DeferredLoginJourneyOutcome outcome;

  /// Present only when [outcome] is [DeferredLoginJourneyOutcome.redeemed].
  final AppHandoffRedeemResponse? redeem;
}

/// Client-side driver for the deferred-login flow against [baseUrl] (a running
/// [StubServer]'s base URL). Pure Dart HTTP — no Flutter dependency — so it is
/// host-safe and dependency-light.
class DeferredLoginJourney {
  DeferredLoginJourney({
    required this.baseUrl,
    this.mountPath = appHandoffDefaultMount,
    required this.platform,
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  final String baseUrl;
  final String mountPath;

  /// `android` or `ios` — the redeem `device.platform` telemetry field.
  final String platform;

  final HttpClient _client;

  /// Runs the mobile-client flow for a captured [carrier] value (the raw
  /// Install Referrer or clipboard text). Returns [DeferredLoginJourneyOutcome.
  /// interactiveFallback] when the carrier is absent/invalid or the redeem
  /// fails; otherwise the minted token.
  Future<DeferredLoginResult> redeemCarrier(String? carrier) async {
    final String? nonce = platform == 'android'
        ? parseAppHandoffInstallReferrer(carrier)
        : parseAppHandoffClipboard(carrier);
    if (nonce == null) {
      return const DeferredLoginResult(
        outcome: DeferredLoginJourneyOutcome.interactiveFallback,
      );
    }
    return redeemNonce(nonce);
  }

  /// Redeems an already-parsed [nonce] directly.
  Future<DeferredLoginResult> redeemNonce(String nonce) async {
    final AppHandoffRedeemRequest body = AppHandoffRedeemRequest(
      nonce: nonce,
      device: AppHandoffDevice(platform: platform),
    );
    final HttpClientRequest request = await _client.postUrl(
      Uri.parse('$baseUrl$mountPath/$appHandoffRedeemPath'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body.toJson()));
    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode != 200) {
      // Any non-200 (the contract's 410 AppHandoffExpired included) means the
      // client falls back to interactive login — no carrier-specific retry.
      return const DeferredLoginResult(
        outcome: DeferredLoginJourneyOutcome.interactiveFallback,
      );
    }
    final Map<String, Object?> json = (jsonDecode(responseBody) as Map).map(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
    return DeferredLoginResult(
      outcome: DeferredLoginJourneyOutcome.redeemed,
      redeem: AppHandoffRedeemResponse.fromJson(json),
    );
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close(force: true);
}
