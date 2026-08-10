import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

const String _baseYaml = '''
app:
  name: base
  retries: 1
  tags: [base]
''';

ConfigLoader loaderOf({
  String base = _baseYaml,
  String? overlay,
  String? development,
  Map<String, String> defines = const <String, String>{},
  String prefix = 'ACME_',
  bool rejectUnknownBlocks = true,
}) => ConfigLoader(
  base: YamlConfigSource.string(base, name: 'base.yaml'),
  overlay: overlay == null
      ? null
      : YamlConfigSource.string(overlay, name: 'overlay.yaml'),
  developmentOverride: development == null
      ? null
      : YamlConfigSource.string(development, name: 'development.yaml'),
  dartDefines: DartDefineOverrides(prefix: prefix, values: defines),
  schema: appSchema(rejectUnknownBlocks: rejectUnknownBlocks),
);

void main() {
  group('layer precedence', () {
    test('base alone produces the base values', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf().load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(name: 'base', retries: 1, tags: <String>['base']),
      );
    });

    test('overlay beats base', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        overlay: 'app:\n  name: overlay\n',
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final AppSettings app = loaded.unwrap().slice(appBlock);
      expect(app.name, 'overlay');
      expect(app.retries, 1, reason: 'a sparse overlay leaves other keys');
    });

    test('development beats overlay', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        overlay: 'app:\n  name: overlay\n',
        development: 'app:\n  name: development\n',
      ).load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'development');
    });

    test('defines beat every YAML layer', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        overlay: 'app:\n  name: overlay\n',
        development: 'app:\n  name: development\n',
        defines: <String, String>{'ACME_APP__NAME': 'define'},
      ).load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'define');
    });

    test(
      'applies the full ladder in exactly base→overlay→dev→define order',
      () async {
        // Each layer wins exactly one key, so the resulting tuple IS the order.
        // Act
        final Result<DieneConfig> loaded = await loaderOf(
          base: 'app:\n  name: base\n  retries: 1\n  tags: [base]\n',
          overlay: 'app:\n  retries: 2\n',
          development: 'app:\n  tags: [development]\n',
          defines: <String, String>{'ACME_APP__NAME': 'define'},
        ).load();

        // Assert
        expect(
          loaded.unwrap().slice(appBlock),
          const AppSettings(
            name: 'define',
            retries: 2,
            tags: <String>['development'],
          ),
        );
      },
    );

    test('reads each layer exactly once', () async {
      // A loader that re-read a layer per lookup would pass every value
      // assertion above while doing four times the IO.
      // Arrange
      final FakeConfigSource base = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'base', 'retries': 0},
      });
      final FakeConfigSource overlay = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      });

      // Act
      await ConfigLoader(
        base: base,
        overlay: overlay,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      ).load();

      // Assert
      expect(base.loadCount, 1);
      expect(overlay.loadCount, 1);
    });

    test('a null overlay and dev source are simply skipped', () async {
      // Arrange
      final FakeConfigSource base = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'base', 'retries': 0},
      });

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: base,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().slice(appBlock).name, 'base');
    });

    test('merges nested maps rather than replacing them', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        base:
            'app:\n'
            '  name: base\n'
            '  retries: 0\n'
            '  nested:\n'
            '    kept: yes\n'
            '    replaced: no\n',
        overlay: 'app:\n  nested:\n    replaced: yes\n',
        rejectUnknownBlocks: false,
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final Map<String, Object?> nested =
          (loaded.unwrap().rawSlice('app').unwrap()['nested']!
              as Map<String, Object?>);
      expect(nested['kept'], 'yes');
      expect(nested['replaced'], 'yes');
    });

    test('replaces a list wholesale — C0 §3 has no append semantics', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        overlay: 'app:\n  tags: [only]\n',
      ).load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).tags, <String>['only']);
    });
  });

  group('final-only validation', () {
    test(
      'accepts a base that is invalid alone but completed by a define',
      () async {
        // The whole point of validating once, at the end: a base with a
        // deliberately impossible default is CORRECT if a later layer fixes it.
        // Act
        final Result<DieneConfig> loaded = await loaderOf(
          base: 'app:\n  name: base\n  retries: -1\n  tags: []\n',
          defines: <String, String>{'ACME_APP__RETRIES': '3'},
        ).load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().slice(appBlock).retries, 3);
      },
    );

    test('accepts a base missing a required key an overlay supplies', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        base: 'app:\n  name: base\n',
        overlay: 'app:\n  retries: 4\n',
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().slice(appBlock).retries, 4);
    });

    test('rejects a final tree that no layer repaired', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        base: 'app:\n  name: service\n  retries: -1\n  tags: []\n',
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });

    test('never exposes an intermediate layer', () async {
      // The only DieneConfig that exists is the validated final one; there is
      // no API returning a partial tree, and the invalid intermediate above
      // proves no intermediate validation ran.
      // Act
      final DieneConfig config = (await loaderOf(
        base: 'app:\n  name: base\n  retries: -1\n  tags: []\n',
        overlay: 'app:\n  retries: 9\n',
      ).load()).unwrap();

      // Assert
      expect(config.raw['app'], isA<Map<String, Object?>>());
      expect(config.slice(appBlock).retries, 9);
    });
  });

  group('indexed list defines', () {
    test(
      'contiguous indexed keys build a list that replaces the YAML one',
      () async {
        // Act
        final Result<DieneConfig> loaded = await loaderOf(
          defines: <String, String>{
            'ACME_APP__TAGS__0': 'first',
            'ACME_APP__TAGS__1': 'second',
          },
        ).load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().slice(appBlock).tags, <String>[
          'first',
          'second',
        ]);
      },
    );

    test('a sparse index is rejected as a value', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{
          'ACME_APP__TAGS__0': 'first',
          'ACME_APP__TAGS__2': 'third',
        },
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });

    test('a list index not starting at zero is rejected', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{'ACME_APP__TAGS__1': 'second'},
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });

    test('mixing indexed and named children is rejected', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{
          'ACME_APP__TAGS__0': 'first',
          'ACME_APP__TAGS__NAMED': 'nope',
        },
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });
  });

  group('define ingress failures propagate the core-utils envelope', () {
    test(
      'an empty path component is reported UNCHANGED, not re-minted',
      () async {
        // Re-minting under a config code would replace a precise coercion
        // vocabulary with a vaguer one. The envelope must arrive as-is.
        // Act
        final Result<DieneConfig> loaded = await loaderOf(
          defines: <String, String>{'ACME_APP____NAME': 'value'},
        ).load();

        // Assert
        expect(loaded, isErr, reason: describe(loaded));
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['util'], 'coercion');
        expect(problem.data['operation'], 'environmentToNestedMap');
        expect(problem.data['code'], 'invalid_input');
        expect(
          configProblemCode(problem).isNone,
          isTrue,
          reason: 'a core-utils code must not read as a config code',
        );
      },
    );

    test('a key that is only the prefix is rejected', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{'ACME_': 'value'},
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['util'], 'coercion');
    });

    test('a scalar used as a parent is a conflict', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': 'scalar',
          'ACME_APP__NAME__CHILD': 'nope',
        },
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'conflict');
    });

    test('two keys normalising onto one path are a conflict', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': 'one',
          'ACME_APP__name': 'two',
        },
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'conflict');
    });

    test('a separator-only path component does not crash the parser', () async {
      // Regression pin. The pre-transplant bespoke override parser special-
      // cased this shape and reached `words.first` on an empty word list,
      // producing a RangeError instead of its own advertised exception.
      // environmentToNestedMap has no such branch: `---` is a non-empty path
      // component, so it becomes an ordinary nested key. Carrying it as text is
      // the documented outcome, NOT a rejection — what matters is that the
      // crash is gone and the result is a value either way.
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{'ACME_APP__---': 'value'},
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().rawSlice('app').unwrap()['---'], 'value');
    });

    test(
      'a separator-only ROOT key is caught by the unknown-block guard',
      () async {
        // At root the same shape IS rejected — not by a parser special case, but
        // by the schema, which is where an unrecognised root key belongs.
        // Act
        final Result<DieneConfig> loaded = await loaderOf(
          defines: <String, String>{'ACME_---': 'value'},
        ).load();

        // Assert
        expect(loaded, isErr, reason: describe(loaded));
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
        expect(
          (problem.data['errors']! as List<Object?>).join(),
          contains('no composed block schema'),
        );
      },
    );
  });

  group('layer read failures short-circuit', () {
    test('a failing base stops the load', () async {
      // Arrange
      final FakeConfigSource overlay = FakeConfigSource(<String, Object?>{});

      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: const FailingConfigSource(name: 'base.yaml'),
        overlay: overlay,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceUnreadable.wireId,
      );
      expect(
        overlay.loadCount,
        0,
        reason: 'a later layer cannot repair a layer that never parsed',
      );
    });

    test('a failing overlay stops the load', () async {
      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: FakeConfigSource(<String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        }),
        overlay: const FailingConfigSource(
          name: 'overlay.yaml',
          code: ConfigProblemCode.sourceNotAMap,
        ),
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      ).load();

      // Assert
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceNotAMap.wireId,
      );
    });

    test('a failing development override stops the load', () async {
      // Act
      final Result<DieneConfig> loaded = await ConfigLoader(
        base: FakeConfigSource(<String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        }),
        developmentOverride: const FailingConfigSource(name: 'dev.yaml'),
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      ).load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['source'], 'dev.yaml');
    });
  });

  group('DartDefineOverrides', () {
    test('projects defines into a nested layer', () {
      // Arrange
      const DartDefineOverrides overrides = DartDefineOverrides(
        prefix: 'ACME_',
        values: <String, String>{'ACME_APP__NAME': 'value'},
      );

      // Act
      final Result<JsonObject> layer = overrides.layer();

      // Assert
      expect(layer, isOk, reason: describe(layer));
      expect(layer.unwrap(), <String, Object?>{
        'app': <String, Object?>{'name': 'value'},
      });
    });

    test('defaults to no values at all', () {
      // Arrange
      const DartDefineOverrides overrides = DartDefineOverrides(
        prefix: 'ACME_',
      );

      // Assert
      expect(overrides.values, isEmpty);
      expect(overrides.layer().unwrap(), isEmpty);
    });

    test('matches its prefix case-insensitively', () async {
      // A host that folds its environment to one case must still contribute.
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{'acme_app__name': 'folded'},
      ).load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'folded');
    });

    test('ignores a key outside the prefix', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{'OTHER_APP__NAME': 'ignored'},
      ).load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'base');
    });

    test('a blank define is UNSET and cannot erase a base value', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': '',
          'ACME_APP__TAGS__0': '',
        },
      ).load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(name: 'base', retries: 1, tags: <String>['base']),
      );
    });

    test('coerces scalars but never decodes JSON or comma lists', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        base: 'app:\n  name: base\n  retries: 0\n  tags: []\n',
        defines: <String, String>{
          'ACME_APP__RETRIES': '7',
          'ACME_APP__NAME': 'first,second',
        },
      ).load();

      // Assert
      final AppSettings app = loaded.unwrap().slice(appBlock);
      expect(app.retries, 7, reason: 'an integer define coerces to int');
      expect(
        app.name,
        'first,second',
        reason: 'a comma string stays the string it is',
      );
    });

    test('a define lands on a differently spelled YAML key', () async {
      // Act
      final Result<DieneConfig> loaded = await loaderOf(
        base: 'app:\n  name: base\n  retries: 0\n  displayName: yaml\n',
        defines: <String, String>{'ACME_APP__DISPLAY_NAME': 'define'},
        rejectUnknownBlocks: false,
      ).load();

      // Assert
      final Map<String, Object?> app = loaded.unwrap().rawSlice('app').unwrap();
      expect(app['displayName'], 'define');
      expect(
        app.keys,
        isNot(contains('display_name')),
        reason: 'the base spelling wins as the output key',
      );
    });
  });
}
