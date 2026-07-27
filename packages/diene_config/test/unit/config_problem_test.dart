import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const ErrorPortal _appPortal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'flutter',
  service: 'app',
  module: 'config',
);

void main() {
  group('ConfigProblemCode', () {
    test('every wire id satisfies the R-E14 snake_case law', () {
      // problemTypeUri enforces this; minting each code proves no id can be
      // added that the ONE builder would reject.
      for (final ConfigProblemCode code in ConfigProblemCode.values) {
        expect(
          problemWireIdPattern.hasMatch(code.wireId),
          isTrue,
          reason: '${code.name} has a non-conforming wire id "${code.wireId}"',
        );
      }
    });

    test('every code carries a 4xx status', () {
      // These are all client-local input failures; a 5xx would tell a caller
      // to retry something that is deterministic in its input.
      for (final ConfigProblemCode code in ConfigProblemCode.values) {
        expect(
          code.status,
          allOf(greaterThanOrEqualTo(400), lessThan(500)),
          reason: '${code.name} has status ${code.status}',
        );
      }
    });

    test('wire ids are unique', () {
      final Set<String> ids = ConfigProblemCode.values
          .map((ConfigProblemCode code) => code.wireId)
          .toSet();
      expect(ids, hasLength(ConfigProblemCode.values.length));
    });
  });

  group('configProblem', () {
    test('mints its type URI through the single C0 §2 builder', () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
      );

      // Assert
      expect(
        problem.type,
        problemTypeUri(
          portal: ErrorPortal.localError,
          version: configProblemVersion,
          id: ConfigProblemCode.schemaInvalid.wireId,
        ),
      );
    });

    test('defaults to the local-error portal', () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceUnreadable,
        message: 'unreadable',
      );

      // Assert
      expect(problem.type, startsWith('https://local.atomi.cloud/docs/local/'));
    });

    test("honours an application's real LPSM portal", () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceNotAMap,
        message: 'not a map',
        portal: _appPortal,
      );

      // Assert
      expect(
        problem.type,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/flutter/app/'
        'config/v1/source_not_a_map',
      );
    });

    test('carries the code, status, and detail prefix', () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.landscapeMissing,
        message: 'no landscape',
      );

      // Assert
      expect(problem.status, 400);
      expect(problem.title, 'no landscape');
      expect(problem.detail, 'config.landscape_missing: no landscape');
      expect(problem.data['code'], 'landscape_missing');
    });

    test('merges extra details alongside the code', () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceUnreadable,
        message: 'unreadable',
        details: <String, Object?>{'source': 'base.yaml'},
      );

      // Assert
      expect(problem.data, <String, Object?>{
        'source': 'base.yaml',
        configProblemCodeKey: 'source_unreadable',
        configProblemProvenanceKey: configProblemValue,
      });
    });

    test('stamps the reserved config provenance marker', () {
      // The marker is what makes an envelope recognisable as config-minted; it
      // is portal-independent, so it is present under any LPSM portal.
      // Act
      final Problem local = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
      );
      final Problem app = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        portal: _appPortal,
      );

      // Assert
      expect(local.data[configProblemProvenanceKey], configProblemValue);
      expect(app.data[configProblemProvenanceKey], configProblemValue);
      expect(configProblemValue, contains(configProblemVersion));
    });

    test('reserves data.code against a conflicting caller detail', () {
      // B3 counterexample: a caller must not be able to ask for one code while
      // smuggling another through `details`. If this were merged into `data`, a
      // schema-invalid request would mint a source-unreadable envelope — the
      // type URI would say `schema_invalid` while `data.code` lied. The reserved
      // key is refused loudly instead.
      expect(
        () => configProblem(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          details: <String, Object?>{'code': 'source_unreadable'},
        ),
        throwsArgumentError,
        reason:
            'a conflicting data.code must never mint a mislabelled envelope',
      );
    });

    test('reserves data.code even when the caller detail agrees', () {
      // The key is owned outright: it is minted from [code], never accepted from
      // the caller, so there is no ambiguous "the caller set it too" path.
      expect(
        () => configProblem(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          details: <String, Object?>{'code': 'schema_invalid'},
        ),
        throwsArgumentError,
      );
    });

    test('reserves the provenance marker against caller details', () {
      // The provenance marker is the discriminator classification trusts, so a
      // caller must not be able to forge it onto an envelope through `details`.
      expect(
        () => configProblem(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          details: <String, Object?>{
            configProblemProvenanceKey: configProblemValue,
          },
        ),
        throwsArgumentError,
      );
    });

    test('is never marked recoverable', () {
      // Every failure here is a deterministic function of its input, so a
      // retry of the identical call cannot change the outcome.
      for (final ConfigProblemCode code in ConfigProblemCode.values) {
        expect(
          configProblem(code: code, message: 'x').recoverable,
          isFalse,
          reason: '${code.name} claims to be retryable',
        );
      }
    });

    test('round-trips through the RFC 9457 JSON envelope', () {
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: <String, Object?>{
          'errors': <String>['app: required block is missing'],
        },
      );

      // Assert
      expect(Problem.fromJson(problem.toJson()), problem);
    });
  });

  group('configFailure', () {
    test('inherits the reserved-code guard from configProblem', () {
      expect(
        () => configFailure<int>(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          details: <String, Object?>{'code': 'source_unreadable'},
        ),
        throwsArgumentError,
      );
    });

    test('wraps the same envelope in an Err', () {
      // Act
      final Err<int> failure = configFailure<int>(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        portal: _appPortal,
        details: <String, Object?>{'block': 'app'},
      );

      // Assert
      expect(failure.isErr, isTrue);
      expect(
        failure.problem,
        configProblem(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          portal: _appPortal,
          details: <String, Object?>{'block': 'app'},
        ),
      );
    });
  });

  group('configProblemCode', () {
    test('reads back a config-owned code', () {
      // Act
      final Option<ConfigProblemCode> code = configProblemCode(
        configProblem(
          code: ConfigProblemCode.sourceNotAMap,
          message: 'not a map',
        ),
      );

      // Assert
      expect(code.isSome, isTrue);
      expect(code.unwrap(), ConfigProblemCode.sourceNotAMap);
    });

    test('returns None for an envelope minted elsewhere', () {
      // A core-utils coercion problem carries `code: invalid_input`, which is
      // that package's vocabulary and must not read as a config code.
      // Arrange
      const Problem foreign = Problem(
        type: 'https://local.atomi.cloud/docs/local/flutter/app/core/v1/x',
        title: 'foreign',
        status: 400,
        data: <String, Object?>{'util': 'coercion', 'code': 'invalid_input'},
      );

      // Assert
      expect(configProblemCode(foreign).isNone, isTrue);
    });

    test('classifies a config problem minted under a real app portal', () {
      // The provenance marker is portal-independent, so classification must
      // recognise the code no matter which LPSM portal minted the envelope.
      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        portal: _appPortal,
      );

      // Assert
      expect(
        configProblemCode(problem).unwrap(),
        ConfigProblemCode.schemaInvalid,
      );
    });

    test('returns None for a foreign envelope carrying a config-shaped code', () {
      // B3 counterexample: another package copies a config-shaped `data.code`.
      // Trusting `data.code` alone would misclassify it; it lacks this package's
      // provenance marker, so it stays None.
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
        title: 'foreign',
        status: 500,
        data: <String, Object?>{'code': 'schema_invalid'},
      );

      // Assert
      expect(configProblemCode(foreign).isNone, isTrue);
    });

    test('returns None for a foreign envelope that reproduces the type-URI suffix '
        'and code', () {
      // Controller counterexample: the type URI is caller-controlled, so a
      // foreign minter can reproduce the exact `…/core/v1/schema_invalid`
      // suffix under its OWN host AND set `data.code: schema_invalid`. Only the
      // reserved provenance marker — which this foreign envelope cannot
      // legitimately carry — keeps it None.
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://foreign.example/docs/other/flutter/app/core/v1/schema_invalid',
        title: 'foreign',
        status: 422,
        data: <String, Object?>{'code': 'schema_invalid'},
      );

      // Assert
      expect(configProblemCode(foreign).isNone, isTrue);
    });

    test('returns None when the provenance marker carries a foreign value', () {
      // The key is present but its value is not this package's identity, so the
      // envelope was minted elsewhere and must not read as config-owned.
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://foreign.example/docs/other/flutter/app/core/v1/schema_invalid',
        title: 'foreign',
        status: 422,
        data: <String, Object?>{
          'code': 'schema_invalid',
          'x-diene-config-provenance': 'someone_else/pkg@v1',
        },
      );

      // Assert
      expect(configProblemCode(foreign).isNone, isTrue);
    });

    test('returns None for an envelope minted under a different contract '
        'version', () {
      // The provenance marker embeds the contract version, so an envelope minted
      // under a different version carries a different marker and is a DIFFERENT
      // problem type — not this version's vocabulary.
      // Arrange
      final Problem otherVersion = Problem(
        type: problemTypeUri(
          portal: ErrorPortal.localError,
          version: configProblemVersion,
          id: ConfigProblemCode.schemaInvalid.wireId,
        ),
        title: 'v2',
        status: 422,
        data: const <String, Object?>{
          'code': 'schema_invalid',
          'x-diene-config-provenance': 'atomicloud/diene_config@v2',
        },
      );

      // Assert
      expect(configProblemCode(otherVersion).isNone, isTrue);
    });

    test('returns None for an envelope with no code at all', () {
      // Arrange
      const Problem bare = Problem(
        type: 'about:blank',
        title: 'bare',
        status: 500,
      );

      // Assert
      expect(configProblemCode(bare).isNone, isTrue);
    });

    test('recognises every declared code', () {
      for (final ConfigProblemCode code in ConfigProblemCode.values) {
        final Problem problem = configProblem(code: code, message: 'x');
        expect(configProblemCode(problem).unwrap(), code);
      }
    });
  });

  group('configProblemVersion', () {
    test('is a valid contract version segment', () {
      expect(configProblemVersion, 'v1');
      expect(problemVersionPattern.hasMatch(configProblemVersion), isTrue);
    });
  });
}
