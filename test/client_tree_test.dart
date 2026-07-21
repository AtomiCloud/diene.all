import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

BackendConfig _backend(String module, String host) => BackendConfig(
  coordinate: LpsmCoordinate(
    landscape: 'lapras',
    platform: 'platform',
    service: 'service',
    module: module,
  ),
  baseUrl: Uri.parse('https://$host'),
);

void main() {
  group('ClientTree', () {
    test('registers and resolves a backend by coordinate', () {
      // Arrange
      final ClientTree tree = ClientTree();
      final BackendConfig backend = _backend('core', 'a.example.com');

      // Act
      final Result<void> registration = tree.register(backend);

      // Assert
      expect(registration.isOk, isTrue);
      expect(tree.resolve(backend.coordinate)?.baseUrl.host, 'a.example.com');
      expect(tree.contains(backend.coordinate), isTrue);
    });

    test('rejects a duplicate registration as a typed Err', () {
      // Arrange
      final ClientTree tree = ClientTree();
      tree.register(_backend('core', 'a.example.com'));

      // Act
      final Result<void> dup = tree.register(_backend('core', 'b.example.com'));

      // Assert
      final Problem p = dup.unwrapErr();
      expect(p.type, BridgeProblems.duplicateBackend);
      expect(p.status, 409);
    });

    test('resolve returns null for an unregistered coordinate', () {
      expect(ClientTree().resolve(_backend('missing', 'x').coordinate), isNull);
    });

    test('LPSM key is landscape.platform.service.module', () {
      expect(
        _backend('core', 'a').coordinate.key,
        'lapras.platform.service.core',
      );
    });
  });
}
