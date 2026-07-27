import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

/// Meta tier: the shipped TestHelper proving itself.
///
/// Two obligations, both discharged here:
///
/// 1. **Assert the asserter.** Every assertion helper is shown ACCEPTING a
///    known-good case and REJECTING a known-bad one. A helper only proven on
///    the happy path is a helper that might never fail.
/// 2. **Fake-versus-real parity.** The same layer matrix is run through the
///    in-memory fakes and through real YAML, and the outcomes are compared. A
///    fake that diverges from the real loader silently invalidates every
///    consumer test written against it.
void main() {
  group('FakeConfigSource', () {
    test('reports the values it was built with', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'fake'},
      });

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect((loaded.unwrap()['app']! as JsonObject)['name'], 'fake');
    });

    test('counts every load', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{});

      // Act
      await source.load();
      await source.load();

      // Assert
      expect(source.loadCount, 2);
    });

    test('is not corrupted by mutating the map it was built from', () async {
      // A fake sharing structure with the caller's map would let an unrelated
      // edit change a fixture halfway through a suite.
      // Arrange
      final Map<String, Object?> seed = <String, Object?>{
        'app': <String, Object?>{'name': 'original'},
      };
      final FakeConfigSource source = FakeConfigSource(seed);

      // Act
      (seed['app']! as Map<String, Object?>)['name'] = 'mutated';

      // Assert
      expect(
        ((await source.load()).unwrap()['app']! as JsonObject)['name'],
        'original',
      );
    });

    test('is not corrupted by mutating a previous load result', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'original'},
      });

      // Act
      final JsonObject first = (await source.load()).unwrap();
      (first['app']! as JsonObject)['name'] = 'mutated';

      // Assert
      expect(
        ((await source.load()).unwrap()['app']! as JsonObject)['name'],
        'original',
      );
    });
  });

  group('FailingConfigSource', () {
    test('fails with its declared code and name', () async {
      // Arrange
      const ConfigSource source = FailingConfigSource(
        name: 'overlay.yaml',
        code: ConfigProblemCode.sourceNotAMap,
        message: 'deliberate',
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceNotAMap.wireId);
      expect(problem.data['source'], 'overlay.yaml');
      expect(problem.title, 'deliberate');
    });

    test('defaults to an unreadable-source failure', () async {
      // Act
      final Result<JsonObject> loaded = await const FailingConfigSource()
          .load();

      // Assert
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceUnreadable.wireId,
      );
    });
  });

  group('FakeLandscapeSource', () {
    test('drives landscape() to its injected value', () {
      // Act
      final Result<String> track = landscape(
        source: const FakeLandscapeSource('lapras'),
      );

      // Assert
      expect(track.unwrap(), 'lapras');
    });

    test('an empty value fakes an absent define', () {
      // Act
      final Result<String> track = landscape(
        source: const FakeLandscapeSource(''),
      );

      // Assert
      expect(track, isErr, reason: describe(track));
      expect(
        track.unwrapErr().data['code'],
        ConfigProblemCode.landscapeMissing.wireId,
      );
    });
  });

  group('ConfigStubBuilder', () {
    test('builds a stub through the REAL schema path', () {
      // Act
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{
          'name': 'stub',
          'retries': 1,
          'tags': <Object?>['x'],
        },
      ).build();

      // Assert
      expect(
        config.slice(appBlock),
        const AppSettings(name: 'stub', retries: 1, tags: <String>['x']),
      );
      expect(
        () => config.raw['app'] = null,
        throwsUnsupportedError,
        reason: 'a stub must be as immutable as a loaded config',
      );
    });

    test('REJECTS a stub the loader would have rejected', () {
      // The known-bad half. A builder that accepted anything would let a test
      // assert against a configuration that cannot exist in production.
      // Assert
      expect(
        () => ConfigStubBuilder().add(appBlock, <String, Object?>{
          'name': '',
          'retries': -1,
        }).build(),
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(contains('INVALID stub'), contains('non-empty string')),
          ),
        ),
      );
    });

    test('addRaw introduces an unknown root key, rejected by default', () {
      // Assert
      expect(
        () => ConfigStubBuilder()
            .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
            .addRaw('extra', <String, Object?>{'x': 1})
            .build(),
        throwsA(isA<ConfigAssertionFailure>()),
      );
    });

    test('addRaw is accepted when unknown blocks are tolerated', () {
      // Act
      final DieneConfig config = ConfigStubBuilder()
          .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
          .addRaw('extra', <String, Object?>{'x': 1})
          .build(rejectUnknownBlocks: false);

      // Assert
      expect(config.rawSlice('extra').unwrap()['x'], 1);
    });

    test('tryBuild returns the failure instead of throwing', () {
      // Act
      final Result<DieneConfig> built = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': '', 'retries': 0},
      ).tryBuild();

      // Assert
      expect(built, isErr, reason: describe(built));
      expect(
        built.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });

    test('tryBuild succeeds on a valid stub', () {
      // Act
      final Result<DieneConfig> built = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'ok', 'retries': 0},
      ).tryBuild();

      // Assert
      expect(built, isOk, reason: describe(built));
    });

    test('chains fluently across several blocks', () {
      // Arrange
      final ConfigBlock<String> apiBlock = ConfigBlock<String>(
        key: 'api',
        decode: (Map<String, Object?> values) => values['baseUrl']! as String,
      );

      // Act
      final DieneConfig config = ConfigStubBuilder()
          .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
          .add(apiBlock, <String, Object?>{'baseUrl': 'https://api.test'})
          .build();

      // Assert
      expect(config.slice(apiBlock), 'https://api.test');
    });
  });

  group('FakeConfigHarness', () {
    test('exposes the fakes it wired, for load-count assertions', () async {
      // Arrange
      final FakeConfigHarness harness = FakeConfigHarness(
        base: <String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        },
        overlay: <String, Object?>{
          'app': <String, Object?>{'name': 'overlay'},
        },
        schema: appSchema(),
      );

      // Act
      await harness.load();

      // Assert
      expect(harness.baseSource.loadCount, 1);
      expect(harness.overlaySource!.loadCount, 1);
      expect(harness.developmentSource, isNull);
    });

    test(
      'omits an overlay and development layer that were not supplied',
      () async {
        // Arrange
        final FakeConfigHarness harness = FakeConfigHarness(
          base: <String, Object?>{
            'app': <String, Object?>{'name': 'base', 'retries': 0},
          },
          schema: appSchema(),
        );

        // Assert
        expect(harness.overlaySource, isNull);
        expect(harness.loader.overlay, isNull);
        expect(harness.loader.developmentOverride, isNull);
        expect((await harness.load()).unwrap().slice(appBlock).name, 'base');
      },
    );

    test('drives the real ConfigLoader, not a reimplementation', () {
      // If the harness rebuilt the ladder itself, every parity test below
      // would be comparing two of its own implementations.
      // Arrange
      final FakeConfigHarness harness = FakeConfigHarness(
        base: <String, Object?>{},
        schema: appSchema(),
      );

      // Assert
      expect(harness.loader, isA<ConfigLoader>());
      expect(harness.loader.schema, same(harness.schema));
      expect(harness.loader.dartDefines.prefix, 'TEST_');
    });
  });

  group('expectOkConfig', () {
    test('returns the configuration on the good case', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'ok', 'retries': 0},
      });

      // Assert
      expect(expectOkConfig(ok).slice(appBlock).name, 'ok');
    });

    test('THROWS on the bad case, naming the schema errors', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Assert
      expect(
        () => expectOkConfig(err),
        throwsA(
          isA<ConfigAssertionFailure>()
              .having(
                (ConfigAssertionFailure error) => error,
                'is a StateError',
                isA<StateError>(),
              )
              .having(
                (ConfigAssertionFailure error) => error.message,
                'message',
                allOf(
                  contains('load FAILED'),
                  contains('app: required block is missing'),
                ),
              ),
        ),
      );
    });
  });

  group('expectErrConfig', () {
    test('returns the problem on the good case', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Assert
      expect(
        expectErrConfig(err).data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });

    test('THROWS on the bad case, showing the configuration it got', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'unexpected', 'retries': 0},
      });

      // Assert
      expect(
        () => expectErrConfig(ok),
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(
              contains('Expected the load to FAIL'),
              contains('unexpected'),
            ),
          ),
        ),
      );
    });
  });

  group('assertConfigProblem', () {
    test('accepts the matching code and returns the problem', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Act
      final Problem problem = assertConfigProblem(
        err,
        ConfigProblemCode.schemaInvalid,
      );

      // Assert
      expect(problem.status, 422);
    });

    test('THROWS on a different config code', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Assert
      expect(
        () => assertConfigProblem(err, ConfigProblemCode.sourceUnreadable),
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(
              contains('Expected config problem "source_unreadable"'),
              contains('"schema_invalid"'),
            ),
          ),
        ),
      );
    });

    test(
      'THROWS on a foreign envelope rather than mis-reading its code',
      () async {
        // A core-utils coercion problem also carries a `code`, and a helper that
        // compared it loosely would report a config code that was never minted.
        // Arrange
        final Result<DieneConfig> err = await ConfigLoader(
          base: FakeConfigSource(<String, Object?>{
            'app': <String, Object?>{'name': 'base', 'retries': 0},
          }),
          dartDefines: const DartDefineOverrides(
            prefix: 'ACME_',
            values: <String, String>{'ACME_APP____NAME': 'bad'},
          ),
          schema: appSchema(),
        ).load();

        // Assert
        expect(err.unwrapErr().data['code'], 'invalid_input');
        expect(
          () => assertConfigProblem(err, ConfigProblemCode.schemaInvalid),
          throwsA(isA<ConfigAssertionFailure>()),
        );
      },
    );

    test('THROWS when the result actually succeeded', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'ok', 'retries': 0},
      });

      // Assert
      expect(
        () => assertConfigProblem(ok, ConfigProblemCode.schemaInvalid),
        throwsA(isA<ConfigAssertionFailure>()),
      );
    });
  });

  group('assertConfigSlice', () {
    test('accepts the matching slice', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'sliced', 'retries': 2},
      ).build();

      // Assert
      expect(
        () => assertConfigSlice(
          config,
          appBlock,
          const AppSettings(name: 'sliced', retries: 2, tags: <String>[]),
        ),
        returnsNormally,
      );
    });

    test('THROWS on a mismatched slice, showing both values', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'actual', 'retries': 0},
      ).build();

      // Assert
      expect(
        () => assertConfigSlice(
          config,
          appBlock,
          const AppSettings(name: 'expected', retries: 0, tags: <String>[]),
        ),
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(contains('expected'), contains('actual')),
          ),
        ),
      );
    });

    test('propagates the StateError for a block that was never composed', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'a', 'retries': 0},
      ).build();
      final ConfigBlock<int> absent = ConfigBlock<int>(
        key: 'absent',
        decode: (_) => 0,
      );

      // Assert
      expect(() => assertConfigSlice(config, absent, 0), throwsStateError);
    });
  });

  group('ConfigAssertionFailure', () {
    test('is catchable as a StateError', () {
      // Assert
      expect(ConfigAssertionFailure('x'), isA<StateError>());
      expect(ConfigAssertionFailure('diagnostic').message, 'diagnostic');
    });
  });

  group('fake-versus-real parity', () {
    // The full matrix, run BOTH ways. The fakes and real YAML must agree on
    // every one of these or a consumer's fake-driven test proves nothing about
    // the loader it will run against in production.
    const String baseYaml = '''
app:
  name: base
  retries: 1
  tags: [base]
''';
    final Map<String, Object?> baseMap = <String, Object?>{
      'app': <String, Object?>{
        'name': 'base',
        'retries': 1,
        'tags': <Object?>['base'],
      },
    };

    const String overlayYaml = 'app:\n  name: overlay\n  retries: 2\n';
    final Map<String, Object?> overlayMap = <String, Object?>{
      'app': <String, Object?>{'name': 'overlay', 'retries': 2},
    };

    const String developmentYaml = 'app:\n  tags: [development]\n';
    final Map<String, Object?> developmentMap = <String, Object?>{
      'app': <String, Object?>{
        'tags': <Object?>['development'],
      },
    };

    Future<Result<DieneConfig>> real({
      String base = baseYaml,
      String? overlay,
      String? development,
      Map<String, String> defines = const <String, String>{},
      bool rejectUnknownBlocks = true,
    }) => ConfigLoader(
      base: YamlConfigSource.string(base, name: 'base.yaml'),
      overlay: overlay == null ? null : YamlConfigSource.string(overlay),
      developmentOverride: development == null
          ? null
          : YamlConfigSource.string(development),
      dartDefines: DartDefineOverrides(prefix: 'TEST_', values: defines),
      schema: appSchema(rejectUnknownBlocks: rejectUnknownBlocks),
    ).load();

    Future<Result<DieneConfig>> fake({
      Map<String, Object?>? base,
      Map<String, Object?>? overlay,
      Map<String, Object?>? development,
      Map<String, String> defines = const <String, String>{},
      bool rejectUnknownBlocks = true,
    }) => FakeConfigHarness(
      base: base ?? baseMap,
      overlay: overlay,
      developmentOverride: development,
      defines: defines,
      schema: appSchema(rejectUnknownBlocks: rejectUnknownBlocks),
    ).load();

    /// Compares both channels: the merged tree on success, the problem code
    /// and error list on failure. Comparing only "both failed" would let two
    /// different failures read as agreement.
    void expectParity(
      Result<DieneConfig> viaFake,
      Result<DieneConfig> viaReal,
      String matrix,
    ) {
      expect(
        viaFake.isOk,
        viaReal.isOk,
        reason: '$matrix: fake=${describe(viaFake)} real=${describe(viaReal)}',
      );
      if (viaFake.isOk) {
        expect(
          viaFake.unwrap().raw,
          viaReal.unwrap().raw,
          reason: '$matrix: merged trees differ',
        );
        expect(
          viaFake.unwrap().slice(appBlock),
          viaReal.unwrap().slice(appBlock),
          reason: '$matrix: typed slices differ',
        );
        return;
      }
      final Problem fakeProblem = viaFake.unwrapErr();
      final Problem realProblem = viaReal.unwrapErr();
      expect(
        fakeProblem.data['code'],
        realProblem.data['code'],
        reason: '$matrix: failure codes differ',
      );
      expect(
        fakeProblem.data['errors'],
        realProblem.data['errors'],
        reason: '$matrix: failure details differ',
      );
    }

    test('base only', () async {
      expectParity(await fake(), await real(), 'base only');
    });

    test('base and overlay', () async {
      expectParity(
        await fake(overlay: overlayMap),
        await real(overlay: overlayYaml),
        'base+overlay',
      );
    });

    test('base, overlay, and development hook', () async {
      expectParity(
        await fake(overlay: overlayMap, development: developmentMap),
        await real(overlay: overlayYaml, development: developmentYaml),
        'base+overlay+dev',
      );
    });

    test('the full ladder with indexed defines', () async {
      const Map<String, String> defines = <String, String>{
        'TEST_APP__NAME': 'define',
        'TEST_APP__TAGS__0': 'first',
        'TEST_APP__TAGS__1': 'second',
      };

      // Act
      final Result<DieneConfig> viaFake = await fake(
        overlay: overlayMap,
        development: developmentMap,
        defines: defines,
      );
      final Result<DieneConfig> viaReal = await real(
        overlay: overlayYaml,
        development: developmentYaml,
        defines: defines,
      );

      // Assert
      expectParity(viaFake, viaReal, 'full ladder');
      expect(
        viaReal.unwrap().slice(appBlock),
        const AppSettings(
          name: 'define',
          retries: 2,
          tags: <String>['first', 'second'],
        ),
      );
    });

    test('a blank define is unset in both', () async {
      const Map<String, String> defines = <String, String>{
        'TEST_APP__NAME': '',
      };
      expectParity(
        await fake(defines: defines),
        await real(defines: defines),
        'blank define',
      );
    });

    test('an INVALID final schema fails identically in both', () async {
      // The parity that matters most: a fake that silently accepted a tree the
      // real loader rejects would hide the failure from every consumer test.
      const String invalidYaml = 'app:\n  name: service\n  retries: -1\n';
      final Map<String, Object?> invalidMap = <String, Object?>{
        'app': <String, Object?>{'name': 'service', 'retries': -1},
      };

      // Act
      final Result<DieneConfig> viaFake = await fake(base: invalidMap);
      final Result<DieneConfig> viaReal = await real(base: invalidYaml);

      // Assert
      expectParity(viaFake, viaReal, 'invalid final schema');
      expect(viaFake, isErr, reason: describe(viaFake));
      expect(
        assertConfigProblem(viaFake, ConfigProblemCode.schemaInvalid).status,
        422,
      );
    });

    test('a malformed define key fails identically in both', () async {
      const Map<String, String> defines = <String, String>{
        'TEST_APP____NAME': 'bad',
      };

      // Act
      final Result<DieneConfig> viaFake = await fake(defines: defines);
      final Result<DieneConfig> viaReal = await real(defines: defines);

      // Assert
      expectParity(viaFake, viaReal, 'malformed define');
      expect(viaFake, isErr, reason: describe(viaFake));
    });

    test('an unknown root key fails identically in both', () async {
      // Act
      final Result<DieneConfig> viaFake = await fake(
        overlay: <String, Object?>{'unknown': <String, Object?>{}},
      );
      final Result<DieneConfig> viaReal = await real(overlay: 'unknown: {}\n');

      // Assert
      expectParity(viaFake, viaReal, 'unknown root key');
      expect(viaFake, isErr, reason: describe(viaFake));
    });

    test('nested-map merging agrees in both', () async {
      // Act
      final Result<DieneConfig> viaFake = await fake(
        base: <String, Object?>{
          'app': <String, Object?>{
            'name': 'base',
            'retries': 0,
            'nested': <String, Object?>{'kept': true, 'replaced': false},
          },
        },
        overlay: <String, Object?>{
          'app': <String, Object?>{
            'nested': <String, Object?>{'replaced': true},
          },
        },
        rejectUnknownBlocks: false,
      );
      final Result<DieneConfig> viaReal = await real(
        base:
            'app:\n'
            '  name: base\n'
            '  retries: 0\n'
            '  nested:\n'
            '    kept: true\n'
            '    replaced: false\n',
        overlay: 'app:\n  nested:\n    replaced: true\n',
        rejectUnknownBlocks: false,
      );

      // Assert
      expectParity(viaFake, viaReal, 'nested merge');
      final Map<String, Object?> nested =
          viaReal.unwrap().rawSlice('app').unwrap()['nested']!
              as Map<String, Object?>;
      expect(nested['kept'], isTrue);
      expect(nested['replaced'], isTrue);
    });

    test('the parity comparator itself REJECTS a divergence', () {
      // Assert the asserter, applied to the parity check: if expectParity
      // could not fail, every parity test above would be vacuous.
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'a', 'retries': 0},
      });
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Assert
      expect(
        () => expectParity(ok, err, 'deliberate divergence'),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => expectParity(
          ok,
          appSchema().validate(<String, Object?>{
            'app': <String, Object?>{'name': 'DIFFERENT', 'retries': 0},
          }),
          'deliberate value divergence',
        ),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
