import 'dart:convert';
import 'dart:typed_data';

import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';
import 'package:dio/dio.dart';

import '../bridge.dart';
import '../transport.dart';

/// The OA3 SDK-wrapper boundary (the dart swagger-adapter analogue).
///
/// A generated retrofit client (see `openapi/service.openapi.yaml` +
/// `scripts/local/generate-sdk.sh`) is driven over a [Dio] whose transport is
/// this engine's [HttpTransport] — so the retry-once profile and the rescue
/// trip apply to every typed SDK call. [ResultSdk.call] then folds each
/// generated-method invocation into `Result<T, Problem>`: retrofit decodes a
/// 2xx payload to `T` (→ `Ok`), and any `DioException` is routed through
/// [toResult] so error bodies classify exactly like the raw bridge
/// (problem body → that `Problem`, non-problem JSON → unexpected-response,
/// connection error / non-JSON → transport-failure).
class OA3Adapter {
  const OA3Adapter._();

  /// Build a [Dio] for a generated SDK whose HTTP flows through [transport]
  /// (wrap it in [RetryOnceTransport] for the hot-path retry-once profile).
  static Dio dio({required Uri baseUrl, required HttpTransport transport}) {
    final Dio client = Dio(BaseOptions(baseUrl: baseUrl.toString()));
    client.httpClientAdapter = _TransportClientAdapter(transport);
    return client;
  }
}

/// Wraps generated-SDK method futures into `Result<T, Problem>`.
class ResultSdk {
  const ResultSdk();

  Future<Result<T>> call<T>(
    Future<T> Function() invoke, {
    String? endpoint,
  }) async {
    try {
      return Ok<T>(await invoke());
    } on DioException catch (error) {
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
        // Never reached on a DioException: retrofit only throws on non-2xx /
        // connection errors, which toResult classifies without decoding.
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
          data: <String, Object?>{if (endpoint != null) 'endpoint': endpoint},
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

/// A dio [HttpClientAdapter] that delegates to the engine's [HttpTransport].
class _TransportClientAdapter implements HttpClientAdapter {
  _TransportClientAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Map<String, String> headers = <String, String>{
      for (final MapEntry<String, Object?> e in options.headers.entries)
        e.key: '${e.value}',
    };
    String? body;
    if (requestStream != null) {
      final List<int> bytes =
          (await requestStream.toList()).expand((Uint8List c) => c).toList();
      body = utf8.decode(bytes, allowMalformed: true);
    } else if (options.data is String) {
      body = options.data as String;
    } else if (options.data != null) {
      body = jsonEncode(options.data);
    }

    final TransportOutcome outcome = await _transport.send(
      HttpRequest(
        method: _method(options.method),
        url: options.uri,
        headers: headers,
        body: body,
      ),
    );
    switch (outcome) {
      case Received(:final response):
        return ResponseBody.fromString(
          response.body,
          response.status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[
              response.headers['content-type'] ?? 'application/json',
            ],
          },
        );
      case NetworkFailure(:final reason):
        throw DioException.connectionError(
          requestOptions: options,
          reason: reason,
        );
    }
  }

  @override
  void close({bool force = false}) {}

  HttpMethod _method(String verb) => switch (verb.toUpperCase()) {
        'POST' => HttpMethod.post,
        'PUT' => HttpMethod.put,
        'PATCH' => HttpMethod.patch,
        'DELETE' => HttpMethod.delete,
        'HEAD' => HttpMethod.head,
        _ => HttpMethod.get,
      };
}
