import 'package:diene_config/config/app_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

DieneConfig stub({String name = 'installed'}) => ConfigStubBuilder().add(
  appBlock,
  <String, Object?>{'name': name, 'retries': 0, 'tags': <Object?>[]},
).build();

ConfigLoader loaderOf({required String base}) => ConfigLoader(
  base: YamlConfigSource.string(base, name: 'base.yaml'),
  dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
  schema: appSchema(),
);

void main() {
  // The holder is process-wide by design, so every test starts from empty.
  setUp(AppConfig.reset);
  tearDown(AppConfig.reset);

  group('the compatibility entrypoint', () {
    test('re-exports the whole public surface', () {
      // The migration promise: one import swap, no other edits. If the
      // re-export were dropped, this file would not compile.
      expect(ConfigProblemCode.schemaInvalid.wireId, 'schema_invalid');
      expect(landscapeDefineKey, 'DIENE_LANDSCAPE');
      expect(c0ConfigContract.provenance.releaseId, 'c0-fixtures-r2');
      expect(appSchema().blocks, hasLength(1));
    });
  });

  group('AppConfig', () {
    test('starts uninstalled', () {
      expect(AppConfig.isInstalled, isFalse);
      expect(AppConfig.maybeInstance.isNone, isTrue);
    });

    test('throws rather than defaulting when read before install', () {
      // A silent default would let the app run against configuration nobody
      // supplied, which is strictly worse than a loud startup failure.
      expect(() => AppConfig.instance, throwsStateError);
    });

    test('returns the installed configuration', () {
      // Arrange
      final DieneConfig config = stub();

      // Act
      AppConfig.install(config);

      // Assert
      expect(AppConfig.isInstalled, isTrue);
      expect(AppConfig.instance, same(config));
      expect(AppConfig.maybeInstance.unwrap(), same(config));
    });

    test('refuses a second install by default', () {
      // Two parts of the app disagreeing about the configuration is a bug,
      // and the loser would be whichever ran first.
      // Arrange
      AppConfig.install(stub());

      // Assert
      expect(() => AppConfig.install(stub(name: 'second')), throwsStateError);
      expect(AppConfig.instance.slice(appBlock).name, 'installed');
    });

    test('replaces on an explicit force', () {
      // Arrange
      AppConfig.install(stub());

      // Act
      AppConfig.install(stub(name: 'forced'), force: true);

      // Assert
      expect(AppConfig.instance.slice(appBlock).name, 'forced');
    });

    test('reset clears the holder', () {
      // Arrange
      AppConfig.install(stub());

      // Act
      AppConfig.reset();

      // Assert
      expect(AppConfig.isInstalled, isFalse);
      expect(() => AppConfig.instance, throwsStateError);
    });
  });

  group('AppConfig.loadAndInstall', () {
    test('installs the configuration a successful load produced', () async {
      // Act
      final Result<DieneConfig> loaded = await AppConfig.loadAndInstall(
        loaderOf(base: 'app:\n  name: loaded\n  retries: 1\n'),
      );

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(AppConfig.isInstalled, isTrue);
      expect(AppConfig.instance.slice(appBlock).name, 'loaded');
      expect(AppConfig.instance, same(loaded.unwrap()));
    });

    test('installs NOTHING when the load fails', () {
      // A failed load must not leave a half-configured process behind.
      // Act & Assert
      return AppConfig.loadAndInstall(
        loaderOf(base: 'app:\n  name: bad\n  retries: -1\n'),
      ).then((Result<DieneConfig> loaded) {
        expect(loaded, isErr, reason: describe(loaded));
        expect(AppConfig.isInstalled, isFalse);
      });
    });

    test(
      'refuses to replace an installed configuration without force',
      () async {
        // Arrange
        AppConfig.install(stub());

        // Act & Assert
        await expectLater(
          AppConfig.loadAndInstall(
            loaderOf(base: 'app:\n  name: second\n  retries: 0\n'),
          ),
          throwsStateError,
        );
        expect(AppConfig.instance.slice(appBlock).name, 'installed');
      },
    );

    test('replaces an installed configuration on force', () async {
      // Arrange
      AppConfig.install(stub());

      // Act
      final Result<DieneConfig> loaded = await AppConfig.loadAndInstall(
        loaderOf(base: 'app:\n  name: replaced\n  retries: 0\n'),
        force: true,
      );

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(AppConfig.instance.slice(appBlock).name, 'replaced');
    });
  });
}
