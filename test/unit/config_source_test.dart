import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

void main() {
  group('YamlConfigSource', () {
    test('converts YAML collections to plain Dart collections', () async {
      // Arrange.
      final YamlConfigSource source = YamlConfigSource.string('''
app:
  name: service
  tags: [one, two]
''');

      // Act.
      final Map<String, Object?> result = await source.load();

      // Assert.
      expect(result, <String, Object?>{
        'app': <String, Object?>{
          'name': 'service',
          'tags': <Object?>['one', 'two'],
        },
      });
    });

    test('reports source names for malformed documents and read failures', () {
      // Arrange.
      final YamlConfigSource scalar = YamlConfigSource.string(
        'scalar',
        name: 'base.yaml',
      );
      final YamlConfigSource failing = YamlConfigSource(
        name: 'overlay.yaml',
        read: () => throw StateError('disk unavailable'),
      );

      // Act and assert.
      expect(
        scalar.load,
        throwsA(
          isA<ConfigSourceException>().having(
            (ConfigSourceException error) => error.source,
            'source',
            'base.yaml',
          ),
        ),
      );
      expect(
        failing.load,
        throwsA(
          isA<ConfigSourceException>().having(
            (ConfigSourceException error) => error.source,
            'source',
            'overlay.yaml',
          ),
        ),
      );
      expect(
        const ConfigSourceException('base.yaml', 'bad').toString(),
        'ConfigSourceException(base.yaml): bad',
      );
    });
  });
}
