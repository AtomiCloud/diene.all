import '../contracts/problem.dart';
import 'carrier.dart';
import 'redeem_client.dart';

/// Reads the Android Play Install Referrer payload and marks it processed.
abstract interface class InstallReferrerSource {
  /// The raw referrer payload, or `null` when none is present.
  Future<String?> read();

  /// Marks the referrer value processed so it is never redeemed twice.
  Future<void> markProcessed();
}

/// Reads and (conditionally) clears the iOS clipboard carrier.
abstract interface class ClipboardCarrierSource {
  /// The clipboard contents, or `null` when empty/unavailable.
  Future<String?> read();

  /// Clears the clipboard ONLY if it still equals [value].
  Future<void> clearIfEquals(String value);
}

/// Result of preparing a deferred login.
sealed class DeferredLoginOutcome {
  const DeferredLoginOutcome();
}

/// A carrier was captured and redeemed — [extraParams] feed
/// `signIn(extraParams:)`.
final class DeferredLoginReady extends DeferredLoginOutcome {
  const DeferredLoginReady(this.extraParams);

  final Map<String, String> extraParams;
}

/// No valid carrier, or redeem returned the generic expiry — fall back to
/// normal interactive login. [problem] is set only for a redeem failure.
final class DeferredLoginFallback extends DeferredLoginOutcome {
  const DeferredLoginFallback([this.problem]);

  final Problem? problem;
}

/// The mobile deferred-login client (C0 §7 / goals/deferred-login.md).
///
/// Reads the store carrier (Android Install Referrer or iOS clipboard),
/// marks it processed / clears the clipboard BEFORE redeem, redeems against
/// `POST {mount}/redeem`, and on success returns the `one_time_token` +
/// `login_hint` extra params. Absent/invalid carrier or an `AppHandoffExpired`
/// response falls back to interactive login — there is no carrier-specific
/// retry loop.
final class DeferredLoginClient {
  const DeferredLoginClient({
    required AppHandoffApi api,
    required DeviceInfo device,
    InstallReferrerSource? referrer,
    ClipboardCarrierSource? clipboard,
  }) : _api = api,
       _device = device,
       _referrer = referrer,
       _clipboard = clipboard;

  final AppHandoffApi _api;
  final DeviceInfo _device;
  final InstallReferrerSource? _referrer;
  final ClipboardCarrierSource? _clipboard;

  /// Attempts a deferred login. Never throws — a failed carrier read simply
  /// falls back to interactive login.
  Future<DeferredLoginOutcome> prepare() async {
    // Android Install Referrer takes priority when present.
    final InstallReferrerSource? referrer = _referrer;
    if (referrer != null) {
      final String? raw = await _safeRead(referrer.read);
      final AppHandoffCarrier? carrier = raw == null
          ? null
          : AppHandoffCarrier.parseAndroidReferrer(raw);
      if (carrier != null) {
        await _safe(referrer.markProcessed);
        return _redeem(carrier);
      }
    }

    // iOS clipboard fallback.
    final ClipboardCarrierSource? clipboard = _clipboard;
    if (clipboard != null) {
      final String? raw = await _safeRead(clipboard.read);
      if (raw != null) {
        final AppHandoffCarrier? carrier = AppHandoffCarrier.parseClipboard(
          raw,
        );
        if (carrier != null) {
          await _safe(() => clipboard.clearIfEquals(raw.trim()));
          return _redeem(carrier);
        }
      }
    }

    return const DeferredLoginFallback();
  }

  Future<DeferredLoginOutcome> _redeem(AppHandoffCarrier carrier) async {
    final result = await _api.redeem(nonce: carrier.nonce, device: _device);
    return result.match(
      onSuccess: (RedeemResult redeemed) => DeferredLoginReady(<String, String>{
        'one_time_token': redeemed.token,
        'login_hint': redeemed.email,
      }),
      onFailure: DeferredLoginFallback.new,
    );
  }

  static Future<String?> _safeRead(Future<String?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  static Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Best-effort side effects; never block the login path.
    }
  }
}
