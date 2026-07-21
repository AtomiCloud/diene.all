import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';

import 'bridge.dart' show BridgeProblems;
import 'config.dart';

/// The LPSM client tree: the ONE place a consumer declares a backend. Keyed by
/// the four-slot coordinate; a duplicate registration is a typed failure, not
/// a throw. (The auth seam is owned by `diene_auth_engine`'s `IAuth`; this lib
/// consumes it, never defines it — see `engine.dart`.)
class ClientTree {
  ClientTree();

  final Map<String, BackendConfig> _byKey = <String, BackendConfig>{};

  /// Register a backend. Returns [Err] on a duplicate coordinate.
  Result<void> register(BackendConfig backend) {
    final String key = backend.coordinate.key;
    if (_byKey.containsKey(key)) {
      return Err<void>(
        Problem(
          type: BridgeProblems.duplicateBackend,
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
