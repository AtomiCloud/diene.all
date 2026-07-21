import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('TestHelper meta contract', () {
    test('fake landscape source returns its deterministic identity', () {
      // Arrange.
      const FakeLandscapeSource source = FakeLandscapeSource('ditto');

      // Act.
      final String value = source.read();

      // Assert.
      expect(value, 'ditto');
    });

    test(
      'fake and YAML sources have identical layered-loader behavior',
      () async {
        // Arrange.
        final ConfigLoader real = ConfigLoader(
          base: YamlConfigSource.string('''
app: {name: base, retries: 1, tags: [base]}
'''),
          overlay: YamlConfigSource.string('''
app: {name: overlay}
'''),
          dartDefines: DartDefineOverrides(
            prefix: 'TEST_',
            values: const <String, String>{'TEST_APP__RETRIES': '3'},
          ),
          schema: appSchema(),
        );
        final FakeConfigHarness fake = FakeConfigHarness(
          base: <String, Object?>{
            'app': <String, Object?>{
              'name': 'base',
              'retries': 1,
              'tags': <Object?>['base'],
            },
          },
          overlay: <String, Object?>{
            'app': <String, Object?>{'name': 'overlay'},
          },
          defines: const <String, String>{'TEST_APP__RETRIES': '3'},
          schema: appSchema(),
        );

        // Act.
        final DieneConfig realConfig = await real.load();
        final DieneConfig fakeConfig = await fake.load();

        // Assert.
        expect(fakeConfig.raw, realConfig.raw);
        expect(fakeConfig.slice(appBlock).retries, 3);
      },
    );

    test('fake source isolates caller data and records loads', () async {
      // Arrange.
      final Map<String, Object?> values = <String, Object?>{
        'app': <String, Object?>{'name': 'original'},
      };
      final FakeConfigSource source = FakeConfigSource(values);

      // Act.
      final Map<String, Object?> first = await source.load();
      (first['app']! as Map<String, Object?>)['name'] = 'changed';
      final Map<String, Object?> second = await source.load();

      // Assert.
      expect((second['app']! as Map<String, Object?>)['name'], 'original');
      expect(source.loadCount, 2);
    });

    test('stub builder validates good fixtures and rejects bad fixtures', () {
      // Arrange.
      final ConfigStubBuilder good = ConfigStubBuilder().add<AppBlock>(
        appBlock,
        <String, Object?>{'name': 'stub', 'retries': 0, 'tags': <Object?>[]},
      );
      final ConfigStubBuilder bad = ConfigStubBuilder().add<AppBlock>(
        appBlock,
        <String, Object?>{'name': '', 'retries': -1, 'tags': <Object?>[]},
      );

      // Act.
      final DieneConfig config = good.build();

      // Assert (including the known-bad half of assert-the-asserter).
      expect(config.slice(appBlock).name, 'stub');
      expect(bad.build, throwsA(isA<ConfigValidationException>()));
    });
  });
}
