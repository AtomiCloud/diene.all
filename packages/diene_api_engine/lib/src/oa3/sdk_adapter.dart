import 'dart:convert';

import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';
import 'package:dio/dio.dart';

import '../bridge.dart';
import '../transport.dart';

/// The OA3 SDK-wrapper boundary (the dart swagger-adapter analogue).
///
/// A generated retrofit client (see `openapi/service.openapi.yaml` +
/// `scripts/local/generate-sdk.sh`) is obtained from a [Backend] via
/// `backend.sdk(GeneratedSdk.new)`, so it runs on the backend's production
/// pipeline (registered base URL + rescue pin, per-resource auth, retry-once,
/// rescue routing). [ResultSdk.call] then folds each generated-method
/// invocation into `Result<T, Problem>`:
///
/// * a 2xx payload retrofit already decoded → `Ok(T)`;
/// * a token failure (a `DioException` whose `error` is a [Problem]) → that
///   `Problem`;
/// * any other `DioException` → routed through [toResult] so error bodies
///   classify exactly like the raw bridge (problem body → that `Problem`,
///   non-problem JSON → unexpected-response, connection error / non-JSON →
///   transport-failure).
class ResultSdk {
  const ResultSdk();

  Future<Result<T>> call<T>(
    Future<T> Function() invoke, {
    String? endpoint,
  }) async {
    try {
      return Ok<T>(await invoke());
    } on DioException catch (error) {
      // A token-resolution failure is surfaced losslessly by the backend
      // adapter as a DioException carrying the auth Problem.
      final Object? cause = error.error;
      if (cause is Problem) {
        return Err<T>(cause);
      }
      final Response<Object?>? response = error.response;
      final TransportOutcome outcome = response != null
          ? Received(
              HttpResponse(
                status: response.statusCode ?? 0,
                body: _bodyString(response.data),
              ),
            )
          : NetworkFailure(error.message ?? error.type.name);
      return toResult<T>(
        outcome,
        decode: (Map<String, Object?> _) =>
            throw StateError('decode unreachable on SDK error path'),
        endpoint: endpoint,
      );
    } on Object catch (error) {
      return Err<T>(
        Problem(
          type: BridgeProblems.transportFailure,
          title: 'Transport failure',
          status: 503,
          detail: 'SDK call threw: $error',
          data: <String, Object?>{'endpoint': ?endpoint},
        ),
      );
    }
  }

  static String _bodyString(Object? data) => switch (data) {
    null => '',
    final String s => s,
    _ => jsonEncode(data),
  };
}
