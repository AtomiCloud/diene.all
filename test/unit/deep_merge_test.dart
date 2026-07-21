import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

void main() {
  group('deepMerge', () {
    test('recursively merges maps and replaces lists', () {
      // Arrange.
      final Map<String, Object?> base = <String, Object?>{
        'app': <String, Object?>{
          'name': 'base',
          'nested': <String, Object?>{'left': 1, 'right': 2},
          'tags': <Object?>['base'],
        },
      };
      final Map<String, Object?> overlay = <String, Object?>{
        'app': <String, Object?>{
          'nested': <String, Object?>{'right': 3},
          'tags': <Object?>['overlay'],
        },
      };

      // Act.
      final Map<String, Object?> result = deepMerge(base, overlay);

      // Assert.
      expect(result, <String, Object?>{
        'app': <String, Object?>{
          'name': 'base',
          'nested': <String, Object?>{'left': 1, 'right': 3},
          'tags': <Object?>['overlay'],
        },
      });
    });

    test('does not share mutable collections with its inputs', () {
      // Arrange.
      final Map<String, Object?> base = <String, Object?>{
        'app': <String, Object?>{
          'tags': <Object?>['base'],
        },
      };

      // Act.
      final Map<String, Object?> result = deepMerge(
        base,
        const <String, Object?>{},
      );
      final Map<String, Object?> app = result['app']! as Map<String, Object?>;
      final List<Object?> tags = app['tags']! as List<Object?>;
      tags.add('changed');

      // Assert.
      expect((base['app']! as Map<String, Object?>)['tags'], <Object?>['base']);
    });
  });
}
