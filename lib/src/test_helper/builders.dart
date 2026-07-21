import 'dart:convert';

import 'package:diene_problems/diene_problems.dart' show Problem;

import '../transport.dart';

/// Builders for the reconciliation matrix. Dependency-light — plain values, no
/// test framework.

/// A well-formed RFC 9457 problem fixture.
Problem problemFixture({
  String type = 'urn:diene:problem:test',
  String title = 'Test problem',
  int status = 400,
  String? detail,
  bool recoverable = false,
  Map<String, Object?> data = const <String, Object?>{},
}) =>
    Problem(
      type: type,
      title: title,
      status: status,
      detail: detail,
      recoverable: recoverable,
      data: data,
    );

/// A 2xx JSON success response.
Received okJson(Map<String, Object?> body, {int status = 200}) => Received(
      HttpResponse(
        status: status,
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );

/// A non-2xx response whose body IS a problem envelope.
Received problemResponse(Problem problem) => Received(
      HttpResponse(
        status: problem.status,
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(problem.toJson()),
      ),
    );

/// A non-2xx JSON body that is NOT a problem (missing type/status).
Received nonProblemJson(Map<String, Object?> body, {int status = 400}) =>
    Received(
      HttpResponse(
        status: status,
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );

/// A non-JSON / status-only failure response.
Received nonJsonResponse({int status = 502, String body = 'Bad Gateway'}) =>
    Received(HttpResponse(status: status, body: body));

/// An opaque network failure outcome.
NetworkFailure networkFailure([String reason = 'connection refused']) =>
    NetworkFailure(reason);
