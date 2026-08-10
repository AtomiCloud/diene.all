import 'dart:async';

import 'package:diene_config/diene_config.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('YamlConfigSource', () {
    test('parses a nested document into plain collections', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string('''
app:
  name: base
  retries: 1
  tags: [alpha, beta]
  nested:
    deep: true
''');

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final JsonObject app = loaded.unwrap()['app']! as JsonObject;
      expect(app['name'], 'base');
      expect(app['retries'], 1);
      expect(app['tags'], <String>['alpha', 'beta']);
      expect((app['nested']! as JsonObject)['deep'], isTrue);
    });

    test('produces types deepMerge can actually merge', () async {
      // The yaml package returns YamlMap/YamlList views, which are NOT
      // Map<String, Object?>. Left unconverted, deepMerge treats a nested map
      // as an opaque scalar and REPLACES it, silently discarding base keys.
      // Arrange
      final ConfigSource source = YamlConfigSource.string('''
app:
  name: base
  retries: 1
''');

      // Act
      final JsonObject base = (await source.load()).unwrap();
      final JsonObject merged = deepMerge(base, <String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      });

      // Assert
      final JsonObject app = merged['app']! as JsonObject;
      expect(app['name'], 'overlay');
      expect(app['retries'], 1, reason: 'the base key must survive the merge');
    });

    test('renders a non-string YAML key through toString', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string(
        '1: one\ntrue: yes\n',
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap(), <String, Object?>{'1': 'one', 'true': 'yes'});
    });

    test('treats an empty document as a layer contributing nothing', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string('');

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap(), isEmpty);
    });

    test('treats a comment-only document as empty', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string('# nothing here\n');

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap(), isEmpty);
    });

    test('rejects a non-map root as source_not_a_map', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string(
        '- one\n- two\n',
        name: 'list.yaml',
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceNotAMap.wireId);
      expect(problem.status, 422);
      expect(problem.data['source'], 'list.yaml');
    });

    test('rejects a scalar root as source_not_a_map', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string('just a string\n');

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceNotAMap.wireId,
      );
    });

    test('reports malformed YAML as source_unreadable', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource.string(
        'app:\n  name: [unterminated\n',
        name: 'broken.yaml',
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceUnreadable.wireId);
      expect(problem.data['source'], 'broken.yaml');
      expect(problem.data['reason'], isA<String>());
    });

    test('reports a throwing read callback as source_unreadable', () async {
      // A missing asset or file arrives exactly this way, since the source
      // never touches the filesystem itself.
      // Arrange
      final ConfigSource source = YamlConfigSource(
        name: 'assets/absent.yaml',
        read: () => throw StateError('asset not found'),
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceUnreadable.wireId);
      expect(problem.data['source'], 'assets/absent.yaml');
      expect('${problem.data['reason']}', contains('asset not found'));
    });

    test('reports a rejected async read as source_unreadable', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource(
        name: 'remote.yaml',
        read: () async => throw const FormatException('network down'),
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceUnreadable.wireId,
      );
    });

    test('accepts an asynchronous read callback', () async {
      // Arrange
      final ConfigSource source = YamlConfigSource(
        name: 'async.yaml',
        read: () async {
          await Future<void>.delayed(Duration.zero);
          return 'app:\n  name: async\n';
        },
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect((loaded.unwrap()['app']! as JsonObject)['name'], 'async');
    });

    test(
      'names the layer in the envelope through the string factory',
      () async {
        // Arrange
        final ConfigSource source = YamlConfigSource.string('- nope\n');

        // Act
        final Result<JsonObject> loaded = await source.load();

        // Assert
        expect(loaded.unwrapErr().data['source'], 'memory');
      },
    );

    test('exposes its read callback and name', () {
      // Arrange
      FutureOr<String> read() => 'app: {}\n';
      final YamlConfigSource source = YamlConfigSource(
        read: read,
        name: 'labelled.yaml',
      );

      // Assert
      expect(source.name, 'labelled.yaml');
      expect(source.read, same(read));
    });
  });
}
