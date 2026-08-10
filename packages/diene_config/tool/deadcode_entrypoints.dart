// Production dead-code root for the published diene_config surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the main
// barrel (diene_config.dart) as an entrypoint, so members reachable ONLY through
// the separately exported c0_config.dart, config/app_config.dart, and
// test_helper.dart sub-libraries — and public members no unit test happens to
// call — get reported as unused. Referencing every public export here keeps the
// production-only dead-code pass honest without any exclusion list (R12: two
// passes, no exclusions).
//
// deadcode.sh copies this file to bin/main.dart inside the production-only
// sandbox, so it lives in the member package where `package:diene_config`
// resolves cleanly (and is excluded from the published archive by .pubignore).
// config/app_config.dart re-exports the whole barrel, which is the migration
// promise it makes — so importing it covers diene_config.dart too, and a second
// import of the barrel would be flagged as unnecessary. c0_config.dart is taken
// separately (with the re-export hidden) because it is a distinct published
// entrypoint whose reachability this pass must prove on its own.
import 'package:diene_config/c0_config.dart';
import 'package:diene_config/config/app_config.dart' hide c0ConfigContract;
import 'package:diene_config/test_helper.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

final ConfigBlock<String> _appBlock = ConfigBlock<String>(
  key: 'app',
  decode: (Map<String, Object?> values) => '${values['name']}',
);

final ConfigBlock<int> _optionalBlock = ConfigBlock<int>(
  key: 'optional',
  required: false,
  decode: (Map<String, Object?> values) => values['count']! as int,
);

Future<void> main() async {
  // --- the failure vocabulary ------------------------------------------------
  _sink(configProblemVersion);
  for (final ConfigProblemCode code in ConfigProblemCode.values) {
    _sink(<Object?>[code.wireId, code.status]);
  }
  final Problem problem = configProblem(
    code: ConfigProblemCode.schemaInvalid,
    message: 'reference the builder',
    portal: ErrorPortal.localError,
    details: <String, Object?>{'block': 'app'},
  );
  _sink(problem);
  _sink(
    configFailure<void>(
      code: ConfigProblemCode.sourceUnreadable,
      message: 'reference the sugar',
    ),
  );
  _sink(configProblemCode(problem).isSome);

  // --- the landscape accessor ------------------------------------------------
  _sink(landscapeDefineKey);
  const LandscapeSource defineSource = DartDefineLandscapeSource(
    value: 'lapras',
  );
  _sink(defineSource.read());
  landscape(source: defineSource).run(_sink).mapErr((Problem p) => p);
  landscape(source: const FakeLandscapeSource('pichu')).run(_sink);

  // --- sources ---------------------------------------------------------------
  final ConfigSource base = YamlConfigSource.string(
    'app:\n  name: base\n',
    name: 'base.yaml',
  );
  final ConfigSource overlay = YamlConfigSource(
    name: 'overlay.yaml',
    read: () => 'app:\n  name: overlay\n',
  );
  _sink((overlay as YamlConfigSource).name);
  (await base.load()).run(_sink);
  (await const FailingConfigSource(name: 'absent.yaml').load()).run(_sink);

  final FakeConfigSource fakeBase = FakeConfigSource(<String, Object?>{
    'app': <String, Object?>{'name': 'fake'},
  });
  (await fakeBase.load()).run(_sink);
  _sink(fakeBase.loadCount);

  // --- the schema surface ----------------------------------------------------
  final ConfigSchema schema = ConfigSchema(
    blocks: <ConfigBlockSchema>[_appBlock, _optionalBlock],
    rejectUnknownBlocks: false,
  );
  _sink(schema.rejectUnknownBlocks);
  _sink(schema.blocks.length);
  _sink(_appBlock.required);
  _sink(_appBlock.decodeUntyped(<String, Object?>{'name': 'erased'}));

  // --- the loader ------------------------------------------------------------
  const DartDefineOverrides defines = DartDefineOverrides(
    prefix: 'ACME_',
    values: <String, String>{
      'ACME_APP__NAME': 'define',
      'ACME_APP__TAGS__0': 'first',
    },
  );
  _sink(defines.prefix);
  _sink(defines.values.length);
  defines.layer().run(_sink);

  final ConfigLoader loader = ConfigLoader(
    base: base,
    overlay: overlay,
    developmentOverride: YamlConfigSource.string('{}', name: 'dev.yaml'),
    dartDefines: defines,
    schema: schema,
  );
  _sink(<Object?>[
    loader.base,
    loader.overlay,
    loader.developmentOverride,
    loader.schema,
    loader.dartDefines,
  ]);

  final Result<DieneConfig> loaded = await loader.load();
  loaded.run((DieneConfig config) {
    _sink(config.raw);
    _sink(config.slice<String>(_appBlock));
    _sink(config.hasSlice(_optionalBlock));
    _sink(config.optionalSlice<int>(_optionalBlock).isNone);
    config.rawSlice('app').run(_sink);
    config.stableProjection().run(_sink);

    // --- the compatibility entrypoint ---------------------------------------
    AppConfig.install(config, force: true);
    _sink(AppConfig.isInstalled);
    _sink(AppConfig.instance.raw.length);
    _sink(AppConfig.maybeInstance.isSome);
    AppConfig.reset();
  });
  (await AppConfig.loadAndInstall(loader, force: true)).run(_sink);
  AppConfig.reset();

  // --- the C0 contract (c0_config.dart sub-library) -------------------------
  const C0ConfigContract contract = c0ConfigContract;
  _sink(contract.projectedCases);
  _sink(contract.provenance.releaseId);
  _sink(contract.provenance.contractVersion);
  _sink(contract.provenance.releaseDigest);
  _sink(contract.provenance.sourceCase);
  _sink(contract.provenance.c0Sections);

  // --- the shipped TestHelper (test_helper.dart sub-library) ----------------
  final DieneConfig stub = ConfigStubBuilder()
      .add<String>(_appBlock, <String, Object?>{'name': 'stub'})
      .addRaw('extra', <String, Object?>{'x': 1})
      .build(rejectUnknownBlocks: false);
  _sink(stub.raw);
  ConfigStubBuilder()
      .add<String>(_appBlock, <String, Object?>{'name': 'stub'})
      .tryBuild(rejectUnknownBlocks: false)
      .run(_sink);

  final FakeConfigHarness harness = FakeConfigHarness(
    base: <String, Object?>{
      'app': <String, Object?>{'name': 'base'},
    },
    overlay: <String, Object?>{
      'app': <String, Object?>{'name': 'overlay'},
    },
    developmentOverride: <String, Object?>{},
    defines: <String, String>{'TEST_APP__NAME': 'define'},
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[_appBlock]),
  );
  _sink(<Object?>[
    harness.base,
    harness.overlay,
    harness.developmentOverride,
    harness.defines,
    harness.prefix,
    harness.schema,
    harness.baseSource,
    harness.overlaySource,
    harness.developmentSource,
    harness.loader,
  ]);
  final Result<DieneConfig> viaHarness = await harness.load();
  _sink(expectOkConfig(viaHarness));
  assertConfigSlice<String>(viaHarness.unwrap(), _appBlock, 'define');

  final Result<DieneConfig> rejected = ConfigSchema(
    blocks: <ConfigBlockSchema>[_appBlock],
  ).validate(<String, Object?>{});
  _sink(expectErrConfig(rejected));
  _sink(assertConfigProblem(rejected, ConfigProblemCode.schemaInvalid));

  // ...and prove the failure type is reachable by rejecting a known-bad case.
  try {
    expectOkConfig(rejected);
  } on ConfigAssertionFailure catch (error) {
    if (error.message.isEmpty) {
      rethrow;
    }
  }

  // --- the consumed core-utils seam -----------------------------------------
  _sink(
    deepMergeAll(<JsonObject>[
      <String, Object?>{
        'app': <String, Object?>{'name': 'base'},
      },
      <String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      },
    ]),
  );
  _sink(canonicalConfigKey('display-name'));
}

/// Consumes a value so the analyzer sees a real use without printing.
void _sink(Object? value) {
  if (value == null && DateTime.now().year < 0) {
    throw StateError('unreachable');
  }
}
