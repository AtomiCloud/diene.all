/// A generic in-process fake HTTP server for consumer journey tests.
///
/// This is `diene_e2e`'s own harness glue — a dependency-light stub server
/// (built on `dart:io`, no test-framework deps) that consumers point their
/// clients at to drive journeys deterministically. Behaviour for a specific
/// contract (e.g. the C0 app-handoff exchange) is mounted onto this one server
/// as route handlers; the harness never spins up a second bespoke server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A recorded inbound request, kept so a journey can assert what the client
/// actually sent.
class StubRequest {
  StubRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  /// Decodes [body] as a JSON object, or throws [FormatException] when it is
  /// not a JSON map.
  Map<String, Object?> jsonBody() {
    final Object? decoded = body.isEmpty ? null : jsonDecode(body);
    if (decoded is! Map) {
      throw FormatException('request body is not a JSON object', body);
    }
    return decoded.map((Object? k, Object? v) => MapEntry(k.toString(), v));
  }
}

/// A canned response a handler returns for a matched route.
class StubResponse {
  const StubResponse({
    this.status = 200,
    this.body = '',
    this.headers = const <String, String>{},
  });

  /// A JSON response: encodes [value] and sets `Content-Type: application/json`
  /// plus `Cache-Control: no-store` (the app-handoff contract default).
  factory StubResponse.json(
    Object? value, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) => StubResponse(
    status: status,
    body: jsonEncode(value),
    headers: <String, String>{
      'content-type': 'application/json',
      'cache-control': 'no-store',
      ...headers,
    },
  );

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// Signature of a route handler: receives the recorded request and returns the
/// response (sync or async).
typedef StubHandler = FutureOr<StubResponse> Function(StubRequest request);

/// A minimal fake HTTP server. Register handlers by `METHOD /path`, then point
/// a client at [baseUrl]. All handled requests are recorded in [requests].
class StubServer {
  StubServer._(this._server)
    : baseUrl = 'http://${_server.address.host}:${_server.port}';

  final HttpServer _server;

  /// The base URL a client should target, e.g. `http://127.0.0.1:54321`.
  final String baseUrl;

  final Map<String, StubHandler> _routes = <String, StubHandler>{};
  final List<StubRequest> _requests = <StubRequest>[];

  /// Every request the server has handled, in arrival order.
  List<StubRequest> get requests => List<StubRequest>.unmodifiable(_requests);

  /// Binds a stub server on an ephemeral loopback port and starts serving.
  static Future<StubServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final StubServer stub = StubServer._(server);
    unawaited(stub._serve());
    return stub;
  }

  /// Registers [handler] for `method path`, e.g. `on('POST', '/app-handoff')`.
  /// A later registration for the same key replaces the earlier one.
  void on(String method, String path, StubHandler handler) {
    _routes[_key(method, path)] = handler;
  }

  /// The handler registered for `method path`, or `null` when the route is not
  /// registered.
  ///
  /// This exists so a caller can invoke a mounted route DIRECTLY, without going
  /// through HTTP. That matters for negative-path assertions: [_handle] does not
  /// wrap handlers in a try, so a handler that throws surfaces to a client as a
  /// dropped connection rather than as the error it threw. A test that asserted
  /// over HTTP would therefore be asserting about the transport instead of about
  /// the handler's own guard. It is also the honest way to check that a `mount`
  /// helper registered the routes it claims to.
  StubHandler? handlerFor(String method, String path) =>
      _routes[_key(method, path)];

  /// Clears the recorded request log (route handlers are left intact).
  void clearRequests() => _requests.clear();

  /// Stops the server, releasing its port.
  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final String body = await utf8.decoder.bind(request).join();
    final Map<String, String> headers = <String, String>{};
    request.headers.forEach((String name, List<String> values) {
      headers[name.toLowerCase()] = values.join(',');
    });
    final StubRequest recorded = StubRequest(
      method: request.method,
      path: request.uri.path,
      headers: headers,
      body: body,
    );
    _requests.add(recorded);

    final StubHandler? handler =
        _routes[_key(request.method, request.uri.path)];
    if (handler == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final StubResponse response = await handler(recorded);
    request.response.statusCode = response.status;
    response.headers.forEach((String name, String value) {
      request.response.headers.set(name, value);
    });
    request.response.write(response.body);
    await request.response.close();
  }

  String _key(String method, String path) => '${method.toUpperCase()} $path';
}
