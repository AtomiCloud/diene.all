import 'bridge.dart';
import 'client_tree.dart';
import 'config.dart';
import 'rescue/router.dart';
import 'rescue/store.dart';
import 'result.dart';
import 'transport.dart';

/// A resolved, callable backend: the config + its per-backend auth binding +
/// the shared engine wiring. Every call goes through the toResult bridge and
/// carries this backend's own token (no cross-backend bleed).
class Backend {
  Backend({
    required this.config,
    required IAuth auth,
    required HttpTransport transport,
    required RescueRouter? rescue,
  })  : _auth = auth,
        _transport = config.retryOnNetworkError
            ? RetryOnceTransport(transport)
            : transport,
        _rescue = rescue;

  final BackendConfig config;
  final IAuth _auth;
  final HttpTransport _transport;
  final RescueRouter? _rescue;

  LpsmCoordinate get coordinate => config.coordinate;

  /// Issue a typed call and fold it into `Result<T, Problem>`.
  ///
  /// Flow: resolve base URL (a live rescue pin wins over the primary while it
  /// is pinned — pin-until-primary-heals) → attach this backend's token →
  /// send with the retry-once profile → on a HARD network failure trip the
  /// dormant rescue router (addresses only, same landscape) and retry once
  /// against the rescued address.
  Future<Result<T>> call<T>({
    required HttpMethod method,
    required String path,
    required T Function(Map<String, Object?> json) decode,
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    final String endpoint = '${config.coordinate.key} $path';
    final Uri? pin = await _rescue?.pinnedFor(coordinate);
    final Uri base = pin ?? config.baseUrl;

    final HttpRequest request = await _buildRequest(
      base: base,
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body,
    );

    final TransportOutcome outcome = await _transport.send(request);

    if (outcome is Received) {
      // If we succeeded through a rescue pin, opportunistically check whether
      // the primary healed and, if so, drop the pin.
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
    final HttpRequest retry = await _buildRequest(
      base: rescued.baseUrl,
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body,
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

  Future<HttpRequest> _buildRequest({
    required Uri base,
    required HttpMethod method,
    required String path,
    required Map<String, String> query,
    required Map<String, String> headers,
    required String? body,
  }) async {
    final Uri url = base.replace(
      path: _joinPath(base.path, path),
      queryParameters: query.isEmpty
          ? null
          : <String, String>{
              ...base.queryParameters,
              ...query,
            },
    );
    final String? token = await _auth.tokenFor(
      coordinate,
      resource: config.authResource,
    );
    return HttpRequest(
      method: method,
      url: url,
      headers: <String, String>{
        if (token != null) 'Authorization': 'Bearer $token',
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
  /// [transport] defaults to the pure-Dart [IoHttpTransport]; Flutter
  /// consumers pass their own seam. [store] backs the rescue cache
  /// (last-known-good kept forever); pass a disk-backed [FileRescueStore] in
  /// production.
  factory ApiEngine.fromConfig(
    ApiEngineConfig config, {
    required IAuth auth,
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
