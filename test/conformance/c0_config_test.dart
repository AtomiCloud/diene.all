import 'package:diene_config/diene_config.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  test(
    'C0 layers base, landscape, development, then dart-define last',
    () async {
      // Arrange. The base is intentionally invalid until later layers repair it;
      // proving intermediate layers are not validated.
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string('''
app:
  name: base
  retries: -1
  tags: [base]
'''),
        overlay: YamlConfigSource.string('''
app:
  name: landscape
  retries: 2
'''),
        developmentOverride: YamlConfigSource.string('''
app:
  name: development
  tags: [development]
'''),
        dartDefines: DartDefineOverrides(
          prefix: 'ACME_',
          values: const <String, String>{
            'ACME_APP__NAME': 'define',
            'ACME_APP__TAGS__0': 'first',
            'ACME_APP__TAGS__1': 'second',
          },
        ),
        schema: appSchema(),
      );

      // Act.
      final DieneConfig config = await loader.load();

      // Assert.
      final AppBlock app = config.slice(appBlock);
      expect(app.name, 'define');
      expect(app.retries, 2);
      expect(app.tags, <String>['first', 'second']);
    },
  );

  test('C0 validation fails before an invalid final config is exposed', () {
    // Arrange.
    final ConfigLoader loader = ConfigLoader(
      base: YamlConfigSource.string('''
app: {name: service, retries: -1, tags: []}
'''),
      dartDefines: DartDefineOverrides(
        prefix: 'ACME_',
        values: const <String, String>{},
      ),
      schema: appSchema(),
    );

    // Act and assert.
    expect(loader.load, throwsA(isA<ConfigValidationException>()));
  });
}
