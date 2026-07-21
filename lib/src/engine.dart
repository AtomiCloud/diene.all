import 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
import 'package:diene_result/diene_result.dart';

import 'bridge.dart';
import 'client_tree.dart';
import 'config.dart';
import 'rescue/router.dart';
import 'rescue/store.dart';
import 'transport.dart';

/// A resolved, callable backend: the config + its per-backend token binding
/// (via the auth-engine `IAuth` seam) + the shared engine wiring. Every call
/// goes through the toResult bridge and carries this backend's OWN token
/// (per-resource, no cross-backend bleed).
class Backend {
  Backend({
    required this.config,
    required IAuth? auth,
    required HttpTransport transport,
    required RescueRouter? rescue,
  })  : _auth = auth,
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

  /// Issue a typed call and fold it into `Result<T>`.
  ///
  /// Resolve the per-resource bearer token through `IAuth` (a token failure is
  /// surfaced as the call's `Err`); resolve the base URL (a live rescue pin
  /// wins while pinned — pin-until-primary-heals); send with the retry-once
  /// profile; on a HARD network failure trip the dormant rescue router
  /// (addresses only, same landscape) and retry once against the rescued
  /// address.
  Future<Result<T>> call<T>({
    required HttpMethod method,
    required String path,
    required T Function(Map<String, Object?> json) decode,
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    final String endpoint = '${config.coordinate.key} $path';

    // Per-resource token (fail-closed: a token error IS the call's error).
    String? bearer;
    final ResourceKey? key = resourceKey;
    if (key != null) {
      final Result<ResourceToken> token = await _auth!.tokenFor(key);
      switch (token) {
        case Ok<ResourceToken>(:final value):
          bearer = value.token;
        case Err<ResourceToken>(:final problem):
          return Err<T>(problem);
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
      return toResult<T>(outcome, decode: decode, endpoint: endpoint);
    }

    // HARD connect-failure past retry-once → dormant rescue.
    final RescueRouter? rescue = _rescue;
    if (rescue == null) {
      return toResult<T>(outcome, decode: decode, endpoint: endpoint);
    }
    final RescueOutcome rescued = await rescue.rescue(coordinate);
    if (rescued is! Rescued) {
      return toResult<T>(outcome, decode: decode, endpoint: endpoint);
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
    return toResult<T>(second, decode: decode, endpoint: endpoint);
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

/// The api-engine facade: builds the LPSM client tree and per-backend rescue
/// wiring from the engine-owned [ApiEngineConfig].
class ApiEngine {
  ApiEngine._({
    required this.tree,
    required Map<String, Backend> backends,
    required this.rescue,
  }) : _backends = backends;

  /// Wire an engine from a validated config slice.
  ///
  /// [auth] is the auth-engine `IAuth` seam (null for a fully anonymous engine).
  /// [transport] defaults to the pure-Dart [IoHttpTransport]. [store] backs the
  /// rescue cache (last-known-good kept forever); pass a disk-backed
  /// [FileRescueStore] in production.
  factory ApiEngine.fromConfig(
    ApiEngineConfig config, {
    IAuth? auth,
    HttpTransport? transport,
    RescueStore? store,
    RescueRouter? rescueOverride,
  }) {
    final HttpTransport t = transport ?? IoHttpTransport();
    final RescueRouter? router = rescueOverride ??
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
