import 'dart:convert';

import 'result.dart';
import 'transport.dart';

/// Baked problem type URIs the bridge mints for the transport/reconciliation
/// classes that are NOT service-authored problems.
class BridgeProblems {
  BridgeProblems._();

  static const String transportFailure = 'urn:diene:problem:transport-failure';
  static const String unexpectedResponse =
      'urn:diene:problem:unexpected-response';
}

/// Guard: does a decoded JSON object structurally look like an RFC 9457
/// problem? (has a string `type` and an int `status`). Mirrors bun's
/// `isProblem`/`isProblemDetail`.
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
/// `Result<T, Problem>` per ARCHITECTURE §4 / lib/bun/api-engine:
///
/// * [NetworkFailure]            → distinct transport-failure [Problem].
/// * 2xx with a JSON body        → `Ok(decode(json))`.
/// * 2xx that fails to decode    → transport-failure [Problem] (status snippet).
/// * non-2xx problem body        → `Err(Problem.fromJson(...))` (incl. nested).
/// * non-2xx JSON-but-not-problem→ wrapped unexpected-response [Problem].
/// * non-2xx non-JSON/empty      → transport-failure [Problem] (status snippet).
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
          data: <String, Object?>{
            if (endpoint != null) 'endpoint': endpoint,
            'reason': reason,
          },
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
      // Successful non-JSON payloads are untyped in v1; a typed call site that
      // asked to decode a JSON body but got none is a transport-failure.
      return Err<T>(
        _transport(
          'success body was not a JSON object',
          response,
          endpoint,
        ),
      );
    }
    try {
      return Ok<T>(decode(json));
    } on Object catch (error) {
      return Err<T>(
        _transport('decode failed: $error', response, endpoint),
      );
    }
  }

  // Error status.
  if (isProblemJson(json)) {
    return Err<T>(Problem.fromJson(json!));
  }
  if (json != null) {
    // JSON, but not a problem — wrap + map into a typed problem.
    return Err<T>(
      Problem(
        type: BridgeProblems.unexpectedResponse,
        title: 'Unexpected service response',
        status: response.status,
        detail: 'Non-problem JSON body',
        instance: endpoint,
        data: <String, Object?>{
          if (endpoint != null) 'endpoint': endpoint,
          'upstreamStatus': response.status,
          'body': json,
        },
      ),
    );
  }
  return Err<T>(
    _transport('non-JSON error body', response, endpoint),
  );
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
      if (endpoint != null) 'endpoint': endpoint,
      'reason': reason,
      'upstreamStatus': response.status,
      if (snippet.isNotEmpty) 'bodySnippet': snippet,
    },
  );
}
