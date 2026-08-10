/// Deferred-login (app-handoff) carrier codec — C0 §7 wire shapes.
///
/// C0 defines the WIRE SHAPES for the deferred-login attribution carrier;
/// `diene_e2e` ships the pure-value codec so the shared fixture and consumer
/// journeys agree on exactly one encoding. No server is implemented here — the
/// mint/redeem behaviour is mounted on a generic stub server by the test
/// harness (`AppHandoffStub`), never re-built as a second app-handoff server.
library;

/// Scheme prefix of the canonical carrier text (C0 §7, Q-I48).
const String appHandoffCarrierScheme = 'atomi-app-handoff';

/// Carrier wire version (C0 §7, Q-I48).
const String appHandoffCarrierVersion = 'v1';

/// The Android Play Install Referrer field name that carries the nonce.
const String appHandoffReferrerField = 'app_handoff';

/// Number of ASCII characters in a valid nonce: 32 random bytes encoded as
/// RFC 4648 base64url WITHOUT padding (C0 §7).
const int appHandoffNonceLength = 43;

final RegExp _base64UrlUnpadded = RegExp(r'^[A-Za-z0-9_-]+$');

/// Whether [nonce] is syntactically a valid C0 §7 nonce: exactly
/// [appHandoffNonceLength] characters from the base64url (unpadded) alphabet.
///
/// This is a shape check only — the nonce is opaque and Logto-meaningless, so
/// no semantic meaning is decoded from it.
bool isValidAppHandoffNonce(String nonce) =>
    nonce.length == appHandoffNonceLength && _base64UrlUnpadded.hasMatch(nonce);

/// Builds the canonical carrier text `atomi-app-handoff:v1:<nonce>` for a
/// syntactically valid [nonce].
///
/// Throws [ArgumentError] if [nonce] is not a valid C0 §7 nonce — the carrier
/// is never allowed to advertise a malformed nonce.
String buildAppHandoffCarrier(String nonce) {
  if (!isValidAppHandoffNonce(nonce)) {
    throw ArgumentError.value(
      nonce,
      'nonce',
      'not a valid C0 app-handoff nonce',
    );
  }
  return '$appHandoffCarrierScheme:$appHandoffCarrierVersion:$nonce';
}

/// Parses the canonical carrier text and returns the nonce, or `null` when the
/// text is absent or does not match `atomi-app-handoff:v1:<valid-nonce>`.
///
/// Per C0 §7 an invalid carrier is treated exactly like an absent one — the
/// client falls back to normal interactive login — so a malformed carrier
/// returns `null` rather than throwing.
String? parseAppHandoffCarrier(String? carrier) {
  if (carrier == null) return null;
  const String prefix = '$appHandoffCarrierScheme:$appHandoffCarrierVersion:';
  if (!carrier.startsWith(prefix)) return null;
  final String nonce = carrier.substring(prefix.length);
  return isValidAppHandoffNonce(nonce) ? nonce : null;
}

/// Builds an Android Play Install Referrer string carrying [nonce] as one
/// `application/x-www-form-urlencoded` field `app_handoff=<percent-encoded
/// canonical carrier>` (C0 §7).
///
/// [extraFields] models coexisting campaign parameters (utm_source, …); they
/// are appended verbatim after the mandatory `app_handoff` field.
String buildAppHandoffInstallReferrer(
  String nonce, {
  Map<String, String> extraFields = const <String, String>{},
}) {
  final String carrier = buildAppHandoffCarrier(nonce);
  final List<String> pairs = <String>[
    '$appHandoffReferrerField=${Uri.encodeQueryComponent(carrier)}',
    for (final MapEntry<String, String> entry in extraFields.entries)
      '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
  ];
  return pairs.join('&');
}

/// Extracts the nonce from an Android Play Install Referrer [referrer], or
/// `null` when it is absent/invalid.
///
/// Per C0 §7 zero or duplicate `app_handoff` fields are treated as absent, and
/// any other campaign fields are ignored.
String? parseAppHandoffInstallReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  final List<String> values = <String>[];
  for (final String pair in referrer.split('&')) {
    if (pair.isEmpty) continue;
    final int eq = pair.indexOf('=');
    final String key = eq < 0 ? pair : pair.substring(0, eq);
    if (Uri.decodeQueryComponent(key) != appHandoffReferrerField) continue;
    final String rawValue = eq < 0 ? '' : pair.substring(eq + 1);
    values.add(Uri.decodeQueryComponent(rawValue));
  }
  // Exactly one occurrence is required; zero or duplicates → absent.
  if (values.length != 1) return null;
  return parseAppHandoffCarrier(values.single);
}

/// Extracts the nonce from iOS clipboard [contents], or `null` when
/// absent/invalid.
///
/// Per C0 §7 the clipboard holds the canonical carrier text and leading/
/// trailing ASCII whitespace may be trimmed before parsing.
String? parseAppHandoffClipboard(String? contents) =>
    parseAppHandoffCarrier(_trimAscii(contents));

String? _trimAscii(String? value) {
  if (value == null) return null;
  int start = 0;
  int end = value.length;
  bool isAsciiWs(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;
  while (start < end && isAsciiWs(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isAsciiWs(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}
