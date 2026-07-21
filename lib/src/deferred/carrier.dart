/// App-handoff carrier v1 (C0 §7, Q-I48).
///
/// The canonical carrier text is exactly `atomi-app-handoff:v1:<nonce>` where
/// the nonce is 32 random bytes RFC 4648 base64url WITHOUT padding (43 ASCII
/// chars). The nonce is opaque and Logto-meaningless; the client NEVER
/// logs/persists it.
final class AppHandoffCarrier {
  const AppHandoffCarrier._(this.nonce);

  /// The opaque 43-char base64url nonce.
  final String nonce;

  static const String _prefix = 'atomi-app-handoff:v1:';
  static final RegExp _nonce = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// The canonical carrier text.
  String get canonicalText => '$_prefix$nonce';

  /// Parses the canonical carrier text; returns `null` when malformed.
  static AppHandoffCarrier? parseCanonical(String raw) {
    if (!raw.startsWith(_prefix)) {
      return null;
    }
    final String nonce = raw.substring(_prefix.length);
    if (!_nonce.hasMatch(nonce)) {
      return null;
    }
    return AppHandoffCarrier._(nonce);
  }

  /// Parses an Android Play Install Referrer payload (an
  /// `application/x-www-form-urlencoded` string). The carrier rides one
  /// `app_handoff=<percent-encoded canonical carrier>` field; zero or duplicate
  /// `app_handoff` fields are treated as absent. Other campaign fields coexist.
  static AppHandoffCarrier? parseAndroidReferrer(String referrer) {
    final List<String> values = <String>[];
    for (final String pair in referrer.split('&')) {
      final int eq = pair.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final String key = pair.substring(0, eq);
      if (key == 'app_handoff') {
        values.add(pair.substring(eq + 1));
      }
    }
    if (values.length != 1) {
      return null;
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(values.single);
    } on Object {
      return null;
    }
    return parseCanonical(decoded);
  }

  /// Parses iOS clipboard content — the canonical carrier text with ASCII
  /// leading/trailing whitespace optionally trimmed.
  static AppHandoffCarrier? parseClipboard(String clipboard) =>
      parseCanonical(clipboard.trim());
}
