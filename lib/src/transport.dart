import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// HTTP verbs the engine issues. The typed OA3 SDK a consumer brings decides
/// which verb each call uses; the engine only carries it to the transport.
enum HttpMethod { get, post, put, patch, delete, head }

/// A transport-level request. Base URL resolution and auth-header attachment
/// happen before this value is built (see the client tree / `IAuth` seam).
@immutable
class HttpRequest {
  const HttpRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
  });

  final HttpMethod method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  HttpRequest withUrl(Uri url) => HttpRequest(
        method: method,
        url: url,
        headers: headers,
        body: body,
      );
}

/// A received HTTP response — ANY status, including 4xx/5xx. A received status
/// is never a network failure and is never retried.
@immutable
class HttpResponse {
  const HttpResponse({
    required this.status,
    this.headers = const <String, String>{},
    this.body = '',
  });

  final int status;
  final Map<String, String> headers;
  final String body;
}

/// Total outcome of a transport send: either a [Received] HTTP response or an
/// opaque [NetworkFailure] (connection refused/reset, DNS blip, TLS failure,
/// timeout) where NO HTTP status was received. Modelled as a sealed value —
/// the transport seam never throws on the hot path.
@immutable
sealed class TransportOutcome {
  const TransportOutcome();
}

@immutable
final class Received extends TransportOutcome {
  const Received(this.response);

  final HttpResponse response;
}

@immutable
final class NetworkFailure extends TransportOutcome {
  const NetworkFailure(this.reason, {this.cause});

  final String reason;
  final Object? cause;
}

/// The transport seam. Implementations MUST classify any received HTTP status
/// as [Received] and only opaque connection-level errors as [NetworkFailure].
abstract interface class HttpTransport {
  Future<TransportOutcome> send(HttpRequest request);
}

/// Retry-once-on-network-error profile (ARCHITECTURE §4 hot path).
///
/// On an opaque [NetworkFailure] the request is retried EXACTLY ONCE over a
/// fresh connection before the failure is surfaced. A [Received] status —
/// even 5xx — is returned immediately and never retried. This is explicitly
/// NOT client-side load balancing: there is no physical-URL list, circuit
/// breaker, or failover ladder here. A [NetworkFailure] returned by this
/// wrapper therefore means a HARD connect-failure (both attempts opaque) — the
/// exact trip point the dormant rescue router keys off.
final class RetryOnceTransport implements HttpTransport {
  const RetryOnceTransport(this._inner);

  final HttpTransport _inner;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    final TransportOutcome first = await _inner.send(request);
    if (first is Received) {
      return first;
    }
    // First attempt was an opaque network failure — retry exactly once over a
    // fresh connection. The inner transport owns connection freshness.
    return _inner.send(request);
  }
}

/// dart:io-backed transport. Pure Dart (no Flutter dependency) so the engine
/// stays host-testable; Flutter consumers may inject any equivalent seam.
final class IoHttpTransport implements HttpTransport {
  IoHttpTransport({Duration? timeout, HttpClient? client})
      : _timeout = timeout ?? const Duration(seconds: 30),
        _client = client ?? HttpClient();

  final Duration _timeout;
  final HttpClient _client;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    try {
      final HttpClientRequest req = await _client
          .openUrl(_verb(request.method), request.url)
          .timeout(_timeout);
      request.headers.forEach(req.headers.set);
      final String? body = request.body;
      if (body != null) {
        req.write(body);
      }
      final HttpClientResponse res = await req.close().timeout(_timeout);
      final String payload = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(_timeout);
      final Map<String, String> headers = <String, String>{};
      res.headers.forEach((String name, List<String> values) {
        headers[name] = values.join(', ');
      });
      return Received(
        HttpResponse(
          status: res.statusCode,
          headers: headers,
          body: payload,
        ),
      );
    } on SocketException catch (error) {
      return NetworkFailure('socket: ${error.message}', cause: error);
    } on HandshakeException catch (error) {
      return NetworkFailure('tls: ${error.message}', cause: error);
    } on TimeoutException catch (error) {
      return NetworkFailure('timeout', cause: error);
    } on HttpException catch (error) {
      return NetworkFailure('http: ${error.message}', cause: error);
    }
  }

  void close() => _client.close(force: true);

  String _verb(HttpMethod method) => switch (method) {
        HttpMethod.get => 'GET',
        HttpMethod.post => 'POST',
        HttpMethod.put => 'PUT',
        HttpMethod.patch => 'PATCH',
        HttpMethod.delete => 'DELETE',
        HttpMethod.head => 'HEAD',
      };
}
