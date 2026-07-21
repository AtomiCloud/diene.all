import 'dart:convert';
import 'dart:typed_data';

import 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';
import 'package:dio/dio.dart';

import 'bridge.dart';
import 'client_tree.dart';
import 'config.dart';
import 'rescue/router.dart';
import 'rescue/store.dart';
import 'transport.dart';

/// Outcome of the shared send pipeline (auth → base/pin → retry-once → rescue),
/// consumed by both `Backend.call` and the generated-SDK Dio adapter.
sealed class _Sent {
  const _Sent();
}

final class _SentReceived extends _Sent {
  const _SentReceived(this.response);
  final HttpResponse response;
}

final class _SentNetworkFailure extends _Sent {
  const _SentNetworkFailure(this.reason);
  final String reason;
}

final class _SentAuthFailed extends _Sent {
  const _SentAuthFailed(this.problem);
  final Problem problem;
}

/// A resolved, callable backend: the config + its per-backend token binding
/// (via the auth-engine `IAuth` seam) + the shared engine wiring. Every call —
/// raw `call<T>` OR a wrapped generated SDK — goes through the SAME pipeline, so
/// the registered base URL, per-resource auth, retry-once transport, dormant
/// rescue routing, and backend identity all apply.
class Backend {
  Backend({
    required this.config,
    required IAuth? auth,
    required HttpTransport transport,
    required RescueRouter? rescue,
  }) : _auth = auth,
       _transport = config.retryOnNetworkError
           ? RetryOnceTransport(transport)
           : transport,
       _rescue = rescue;

  final BackendConfig config;
  final IAuth? _auth;
  final HttpTransport _transport;
  final RescueRouter? _rescue;

  LpsmCoordinate get coordinate => config.coordinate;

  /// The per-resource key handed to `IAuth`, or null when the backend needs no
  /// token. `resourceName` occupies the M slot of the LPSM coordinate.
  ResourceKey? get resourceKey {
    final String? resource = config.resourceName;
    if (resource == null || _auth == null) {
      return null;
    }
    return ResourceKey(
      platform: config.coordinate.platform,
      landscape: config.coordinate.landscape,
      service: config.coordinate.service,
      resourceName: resource,
    );
  }

  /// Issue a typed JSON call and fold it into `Result<T>` via the toResult
  /// bridge.
  Future<Result<T>> call<T>({
    required HttpMethod method,
    required String path,
    required T Function(Map<String, Object?> json) decode,
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    final String endpoint = '${config.coordinate.key} $path';
    final _Sent sent = await _pipeline(
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body,
    );
    return switch (sent) {
      _SentReceived(:final response) => toResult<T>(
        Received(response),
        decode: decode,
        endpoint: endpoint,
      ),
      _SentNetworkFailure(:final reason) => toResult<T>(
        NetworkFailure(reason),
        decode: decode,
        endpoint: endpoint,
      ),
      _SentAuthFailed(:final problem) => Err<T>(problem),
    };
  }

  /// Build a generated OA3 SDK bound to THIS backend's production pipeline.
  /// [factory] is a generated root-client constructor (e.g. `ServiceSdk.new`);
  /// every call it makes flows through this backend's base URL (incl. a live
  /// rescue pin), per-resource auth, retry-once, and rescue routing. Wrap the
  /// resulting client's calls with [ResultSdk.call].
  S sdk<S>(S Function(Dio dio) factory) => factory(dio());

  /// The Dio a generated SDK runs on: its HTTP is delegated to this backend's
  /// pipeline via [BackendClientAdapter].
  Dio dio() {
    final Dio client = Dio(BaseOptions(baseUrl: config.baseUrl.toString()));
    client.httpClientAdapter = BackendClientAdapter(this);
    return client;
  }

  /// Shared send pipeline: resolve the per-resource bearer (a token failure is
  /// surfaced), resolve the base URL (a live rescue pin wins while pinned —
  /// pin-until-primary-heals), send with the retry-once profile, and on a HARD
  /// network failure trip the dormant rescue router (addresses only, same
  /// landscape) and retry once against the rescued address.
  Future<_Sent> _pipeline({
    required HttpMethod method,
    required String path,
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    String? bearer;
    final ResourceKey? key = resourceKey;
    if (key != null) {
      final Result<ResourceToken> token = await _auth!.tokenFor(key);
      switch (token) {
        case Ok<ResourceToken>(:final value):
          bearer = value.token;
        case Err<ResourceToken>(:final problem):
          return _SentAuthFailed(problem);
      }
    }

    final Uri? pin = await _rescue?.pinnedFor(coordinate);
    final Uri base = pin ?? config.baseUrl;
    final HttpRequest request = _buildRequest(
      base: base,
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body,
      bearer: bearer,
    );

    final TransportOutcome outcome = await _transport.send(request);
    if (outcome is Received) {
      if (pin != null && outcome.response.status < 500) {
        await _maybeHeal();
      }
      return _SentReceived(outcome.response);
    }

    final RescueRouter? rescue = _rescue;
    if (rescue == null) {
      return _SentNetworkFailure((outcome as NetworkFailure).reason);
    }
    final RescueOutcome rescued = await rescue.rescue(coordinate);
    if (rescued is! Rescued) {
      return _SentNetworkFailure((outcome as NetworkFailure).reason);
    }
    final HttpRequest retry = _buildRequest(
      base: rescued.baseUrl,
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body,
      bearer: bearer,
    );
    final TransportOutcome second = await _transport.send(retry);
    return second is Received
        ? _SentReceived(second.response)
        : _SentNetworkFailure((second as NetworkFailure).reason);
  }

  Future<void> _maybeHeal() async {
    final RescueRouter? rescue = _rescue;
    if (rescue == null) {
      return;
    }
    if (await rescue.probeHealthy(config.baseUrl)) {
      await rescue.onPrimaryHealed(coordinate);
    }
  }

  HttpRequest _buildRequest({
    required Uri base,
    required HttpMethod method,
    required String path,
    required Map<String, String> query,
    required Map<String, String> headers,
    required String? body,
    required String? bearer,
  }) {
    final Uri url = base.replace(
      path: _joinPath(base.path, path),
      queryParameters: query.isEmpty
          ? null
          : <String, String>{...base.queryParameters, ...query},
    );
    return HttpRequest(
      method: method,
      url: url,
      headers: <String, String>{
        if (bearer != null) 'Authorization': 'Bearer $bearer',
        ...headers,
      },
      body: body,
    );
  }

  static String _joinPath(String basePath, String path) {
    final String left = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final String right = path.startsWith('/') ? path : '/$path';
    return '$left$right';
  }
}

/// A dio [HttpClientAdapter] that drives a generated SDK through a [Backend]'s
/// production pipeline. Received → dio [ResponseBody]; a HARD network failure →
/// `DioException.connectionError`; a token failure → a `DioException` carrying
/// the auth [Problem] (surfaced losslessly by [ResultSdk]).
class BackendClientAdapter implements HttpClientAdapter {
  BackendClientAdapter(this._backend);

  final Backend _backend;

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
      final List<int> bytes = (await requestStream.toList())
          .expand((Uint8List c) => c)
          .toList();
      body = utf8.decode(bytes, allowMalformed: true);
    } else if (options.data is String) {
      body = options.data as String;
    } else if (options.data != null) {
      body = jsonEncode(options.data);
    }

    final _Sent sent = await _backend._pipeline(
      method: _method(options.method),
      path: options.uri.path,
      query: options.uri.queryParameters,
      headers: headers,
      body: body,
    );
    switch (sent) {
      case _SentReceived(:final response):
        return ResponseBody.fromString(
          response.body,
          response.status,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[
              response.headers['content-type'] ?? 'application/json',
            ],
          },
        );
      case _SentNetworkFailure(:final reason):
        throw DioException.connectionError(
          requestOptions: options,
          reason: reason,
        );
      case _SentAuthFailed(:final problem):
        throw DioException(requestOptions: options, error: problem);
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

/// The api-engine facade: builds the LPSM client tree and per-backend rescue
/// wiring from the engine-owned [ApiEngineConfig].
class ApiEngine {
  ApiEngine._({
    required this.tree,
    required Map<String, Backend> backends,
    required this.rescue,
  }) : _backends = backends;

  /// Wire an engine from a validated config slice.
  factory ApiEngine.fromConfig(
    ApiEngineConfig config, {
    IAuth? auth,
    HttpTransport? transport,
    RescueStore? store,
    RescueRouter? rescueOverride,
  }) {
    final HttpTransport t = transport ?? IoHttpTransport();
    final RescueRouter? router =
        rescueOverride ??
        (config.rescue.enabled
            ? RescueRouter(
                config: config.rescue,
                store: store ?? InMemoryRescueStore(),
                transport: t,
              )
            : null);
    final ClientTree tree = ClientTree();
    final Map<String, Backend> backends = <String, Backend>{};
    for (final BackendConfig backendConfig in config.backends) {
      final Result<void> registration = tree.register(backendConfig);
      if (registration case Err<void>(:final problem)) {
        throw StateError('backend registration failed: ${problem.detail}');
      }
      backends[backendConfig.coordinate.key] = Backend(
        config: backendConfig,
        auth: auth,
        transport: t,
        rescue: router,
      );
    }
    return ApiEngine._(tree: tree, backends: backends, rescue: router);
  }

  final ClientTree tree;
  final Map<String, Backend> _backends;
  final RescueRouter? rescue;

  /// Resolve a callable backend by coordinate.
  Backend? backend(LpsmCoordinate coordinate) => _backends[coordinate.key];
}
