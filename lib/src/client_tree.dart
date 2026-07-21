import 'config.dart';
import 'result.dart';

/// The auth seam. auth-engine's per-resource token retriever plugs in here.
/// Tokens resolve PER BACKEND (multi-backend: one app, many backends) — never
/// a shared/singleton token. Returns null when the backend needs no token.
abstract interface class IAuth {
  Future<String?> tokenFor(LpsmCoordinate coordinate, {String? resource});
}

/// An `IAuth` that never attaches a token (anonymous backends / tests).
class AnonymousAuth implements IAuth {
  const AnonymousAuth();

  @override
  Future<String?> tokenFor(LpsmCoordinate coordinate,
          {String? resource}) async =>
      null;
}

/// The LPSM client tree: the ONE place a consumer declares a backend. Keyed by
/// the four-slot coordinate; a duplicate registration is a typed failure, not
/// a throw.
class ClientTree {
  ClientTree();

  final Map<String, BackendConfig> _byKey = <String, BackendConfig>{};

  /// Register a backend. Returns [Err] on a duplicate coordinate.
  Result<void> register(BackendConfig backend) {
    final String key = backend.coordinate.key;
    if (_byKey.containsKey(key)) {
      return Err<void>(
        Problem(
          type: 'urn:diene:problem:duplicate-backend',
          title: 'Duplicate backend registration',
          status: 409,
          detail: key,
          data: <String, Object?>{'coordinate': backend.coordinate.toMap()},
        ),
      );
    }
    _byKey[key] = backend;
    return const Ok<void>(null);
  }

  BackendConfig? resolve(LpsmCoordinate coordinate) => _byKey[coordinate.key];

  Iterable<BackendConfig> get backends => _byKey.values;

  bool contains(LpsmCoordinate coordinate) =>
      _byKey.containsKey(coordinate.key);
}
