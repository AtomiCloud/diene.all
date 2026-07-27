import 'dart:convert';

import 'package:diene_problems/diene_problems.dart'
    show ErrorPortal, Problem, problemTypeUri;
import 'package:diene_result/diene_result.dart';

import 'transport.dart';

/// api-engine's own client-side problem type URIs, minted through the ONE
/// owned builder in `diene_problems` (never hand-formatted here — C0 §2). These
/// are api-engine's OWN problems (transport/reconciliation failures a client
/// raises); the `Problem` envelope type itself is owned by `diene_result`.
class BridgeProblems {
  BridgeProblems._();

  /// Client-local portal: api-engine's transport problems have no service
  /// backend context. A real app can override the portal via [configure].
  static ErrorPortal portal = ErrorPortal.localError;

  static String _uri(String id) =>
      problemTypeUri(portal: portal, version: 'v1', id: id);

  // R-E14 WIRE-ID LAW. These ids are snake_case, NOT kebab. The published
  // `problemWireIdPattern` is `^[a-z][a-z0-9_]*$`, so a hyphen is rejected at
  // construction:
  //   Invalid argument (id): must be a non-empty single path segment matching
  //   its contract pattern: "transport-failure"
  // All four were kebab and every call site that built one threw — which is why
  // ClientTree.register, toResult and the whole contract-parity suite failed the
  // moment the tiers could finally run. The ids are the ONLY composition here
  // (`_uri` passes its argument straight through), so there is no second half to
  // this fix; `bridge_wire_id_test.dart` asserts each one against the PUBLISHED
  // pattern rather than a local copy, so the two cannot drift apart again.
  static String get transportFailure => _uri('transport_failure');
  static String get unexpectedResponse => _uri('unexpected_response');
  static String get duplicateBackend => _uri('duplicate_backend');
  static String get authTokenUnavailable => _uri('auth_token_unavailable');
}

/// Guard: does a decoded JSON object structurally look like an RFC 9457
/// problem? (string `type` + int `status`).
bool isProblemJson(Object? value) =>
    value is Map<String, Object?> &&
    value['type'] is String &&
    value['status'] is int;

/// Guard: does [body] parse as a JSON object?
Map<String, Object?>? tryDecodeObject(String body) {
  if (body.trim().isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// The full error reconciliation: folds a [TransportOutcome] into
/// `Result<T>` (error channel is `diene_result`'s `Problem`):
///
/// * [NetworkFailure]             → transport-failure [Problem].
/// * 2xx JSON                     → `Ok(decode(json))`.
/// * 2xx non-JSON / decode failure→ transport-failure [Problem].
/// * non-2xx valid problem body   → `Err(Problem.fromJson)` (incl. nested).
/// * non-2xx JSON but not/invalid problem → unexpected-response [Problem].
/// * non-2xx non-JSON / status-only → transport-failure [Problem].
///
/// No thrown exception ever escapes; the caller always gets a [Result].
Result<T> toResult<T>(
  TransportOutcome outcome, {
  required T Function(Map<String, Object?> json) decode,
  String? endpoint,
}) {
  switch (outcome) {
    case NetworkFailure(:final reason):
      return Err<T>(
        Problem(
          type: BridgeProblems.transportFailure,
          title: 'Transport failure',
          status: 503,
          detail: reason,
          data: <String, Object?>{'endpoint': ?endpoint, 'reason': reason},
        ),
      );
    case Received(:final response):
      return _fromResponse<T>(response, decode: decode, endpoint: endpoint);
  }
}

Result<T> _fromResponse<T>(
  HttpResponse response, {
  required T Function(Map<String, Object?> json) decode,
  String? endpoint,
}) {
  final bool ok = response.status >= 200 && response.status < 300;
  final Map<String, Object?>? json = tryDecodeObject(response.body);

  if (ok) {
    if (json == null) {
      return Err<T>(
        _transport('success body was not a JSON object', response, endpoint),
      );
    }
    try {
      return Ok<T>(decode(json));
    } on Object catch (error) {
      return Err<T>(_transport('decode failed: $error', response, endpoint));
    }
  }

  // Error status: a valid RFC 9457 problem body wins; anything else is wrapped.
  if (isProblemJson(json)) {
    try {
      return Err<T>(Problem.fromJson(json!));
    } on FormatException {
      // Structurally problem-ish but not a valid envelope → unexpected.
    }
  }
  if (json != null) {
    return Err<T>(
      Problem(
        type: BridgeProblems.unexpectedResponse,
        title: 'Unexpected service response',
        status: response.status,
        detail: 'Non-problem JSON body',
        instance: endpoint,
        data: <String, Object?>{
          'endpoint': ?endpoint,
          'upstreamStatus': response.status,
          'body': json,
        },
      ),
    );
  }
  return Err<T>(_transport('non-JSON error body', response, endpoint));
}

Problem _transport(String reason, HttpResponse response, String? endpoint) {
  final String snippet = response.body.length > 256
      ? '${response.body.substring(0, 256)}…'
      : response.body;
  return Problem(
    type: BridgeProblems.transportFailure,
    title: 'Transport failure',
    status: response.status == 0 ? 503 : response.status,
    detail: reason,
    instance: endpoint,
    data: <String, Object?>{
      'endpoint': ?endpoint,
      'reason': reason,
      'upstreamStatus': response.status,
      if (snippet.isNotEmpty) 'bodySnippet': snippet,
    },
  );
}
