import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> _coordinate(String module) => <String, Object?>{
      'landscape': 'lapras',
      'platform': 'platform',
      'service': 'service',
      'module': module,
    };

Map<String, Object?> _validSlice(
        {List<String> modules = const <String>['core']}) =>
    <String, Object?>{
      'backends': <Object?>[
        for (final String m in modules)
          <String, Object?>{
            'coordinate': _coordinate(m),
            'baseUrl': 'https://$m.example.com',
            'resourceName': m,
          },
      ],
      'rescue': <String, Object?>{
        'enabled': true,
        'issuer': 'https://auth.atomi.cloud',
        'catalogHosts': <String>['r2.example.com'],
        'endpointSuffixAllowlist': <String>['.cluster.atomi.cloud'],
      },
    };

void main() {
  group('ApiEngineConfig.fromMap', () {
    test('parses a valid slice', () {
      // Act
      final ApiEngineConfig config = ApiEngineConfig.fromMap(_validSlice());

      // Assert
      expect(config.backends, hasLength(1));
      expect(config.backends.single.baseUrl.host, 'core.example.com');
      expect(config.rescue.enabled, isTrue);
      expect(config.rescue.issuer, Uri.parse('https://auth.atomi.cloud'));
      expect(config.rescue.endpointSuffixAllowlist,
          contains('.cluster.atomi.cloud'));
    });

    test('fails fast on zero backends', () {
      final Map<String, Object?> slice = _validSlice()
        ..['backends'] = <Object?>[];
      expect(() => ApiEngineConfig.fromMap(slice), throwsFormatException);
    });

    test('fails fast on duplicate backend coordinates', () {
      final Map<String, Object?> slice =
          _validSlice(modules: <String>['core', 'core']);
      expect(() => ApiEngineConfig.fromMap(slice), throwsFormatException);
    });

    test('fails fast on a missing rescue block', () {
      final Map<String, Object?> slice = _validSlice()..remove('rescue');
      expect(() => ApiEngineConfig.fromMap(slice), throwsFormatException);
    });
  });

  group('engine-owned schema', () {
    test('describes the block and is stable under schemaEquals', () {
      final Map<String, Object?> schema = ApiEngineConfig.schema;
      expect(schema[r'$id'], 'urn:diene:config-block:api-engine');
      expect((schema['required'] as List<Object?>),
          containsAll(<String>['backends', 'rescue']));
      expect(ApiEngineConfig.schemaEquals(ApiEngineConfig.schema), isTrue);
    });
  });
}
