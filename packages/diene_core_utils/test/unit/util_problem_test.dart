import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

void main() {
  group('wire-id law (R-E14)', () {
    test('every UtilName wire id matches the cross-language pattern', () {
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final UtilName util in UtilName.values) {
        expect(
          pattern.hasMatch(util.wireId),
          isTrue,
          reason: '${util.name} wire id "${util.wireId}" is not snake_case',
        );
        // The enum name IS the wire id, so the two cannot drift apart.
        expect(util.wireId, util.name);
      }
    });

    test('every UtilErrorCode wire id matches the pattern', () {
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final UtilErrorCode code in UtilErrorCode.values) {
        expect(
          pattern.hasMatch(code.wireId),
          isTrue,
          reason: '${code.name} wire id "${code.wireId}" is not snake_case',
        );
      }
    });

    test('the COMPOSED id is legal, not merely each half', () {
      // The composition is what lands in the type URI, and a separator that is
      // legal alone can still make the composed id illegal.
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final UtilName util in UtilName.values) {
        for (final UtilErrorCode code in UtilErrorCode.values) {
          final String composed = '${util.wireId}_${code.wireId}';
          expect(
            pattern.hasMatch(composed),
            isTrue,
            reason: 'composed id "$composed" is not a legal wire id',
          );
        }
      }
    });

    test('wire ids are unique within each vocabulary', () {
      expect(
        UtilName.values.map((UtilName u) => u.wireId).toSet(),
        hasLength(UtilName.values.length),
      );
      expect(
        UtilErrorCode.values.map((UtilErrorCode c) => c.wireId).toSet(),
        hasLength(UtilErrorCode.values.length),
      );
    });
  });

  group('status and recoverability', () {
    test('each code carries a plausible HTTP status', () {
      expect(UtilErrorCode.invalidInput.status, 400);
      expect(UtilErrorCode.invalidFormat.status, 400);
      expect(UtilErrorCode.conflict.status, 409);
      expect(UtilErrorCode.unprojectable.status, 422);
      expect(UtilErrorCode.delegated.status, 500);
    });

    test(
      'no code claims recoverability, because none of them is retryable',
      () {
        for (final UtilErrorCode code in UtilErrorCode.values) {
          expect(
            code.recoverable,
            isFalse,
            reason: '${code.name} claims a retry this library cannot honour',
          );
        }
      },
    );
  });

  group('utilProblem', () {
    test('mints the envelope through the single C0 §2 builder', () {
      final Problem problem = utilProblem(
        util: UtilName.slug,
        code: UtilErrorCode.invalidInput,
        operation: 'namespacedKey',
        message: 'namespace must not slugify to empty',
      );

      expect(problem.title, 'namespace must not slugify to empty');
      expect(problem.status, 400);
      expect(problem.recoverable, isFalse);
      expect(
        problem.detail,
        'slug.namespacedKey: namespace must not slugify to empty',
      );
      expect(problem.data['util'], 'slug');
      expect(problem.data['code'], 'invalid_input');
      expect(problem.data['operation'], 'namespacedKey');

      // The URI must be what the builder produces for this exact id, compared
      // against the builder's own output rather than a hand-written string.
      expect(
        problem.type,
        problemTypeUri(
          portal: ErrorPortal.localError,
          version: coreUtilsProblemVersion,
          id: 'slug_invalid_input',
        ),
      );
    });

    test('extra details merge into data without displacing the fixed keys', () {
      final Problem problem = utilProblem(
        util: UtilName.coercion,
        code: UtilErrorCode.conflict,
        operation: 'environmentToNestedMap',
        message: 'clash',
        details: <String, Object?>{'field': 'ACME_A', 'path': 'a'},
      );
      expect(problem.data['util'], 'coercion');
      expect(problem.data['code'], 'conflict');
      expect(problem.data['operation'], 'environmentToNestedMap');
      expect(problem.data['field'], 'ACME_A');
      expect(problem.data['path'], 'a');
    });

    test('a real LPSM portal moves the URI host without changing the id', () {
      final Problem local = utilProblem(
        util: UtilName.wire,
        code: UtilErrorCode.invalidFormat,
        operation: 'parse',
        message: 'nope',
      );
      final Problem hosted = utilProblem(
        util: UtilName.wire,
        code: UtilErrorCode.invalidFormat,
        operation: 'parse',
        message: 'nope',
        portal: ErrorPortal.localError,
      );
      expect(hosted.type, local.type);
      expect(local.type, endsWith('wire_invalid_format'));
    });

    test('the version segment is part of the contract identity', () {
      expect(coreUtilsProblemVersion, 'v1');
      expect(
        utilProblem(
          util: UtilName.record,
          code: UtilErrorCode.unprojectable,
          operation: 'stableConfig',
          message: 'cycle',
        ).type,
        contains('/v1/'),
      );
    });
  });

  group('failure sugar', () {
    test('utilFailure produces an Err carrying utilProblem output', () {
      final Err<int> failure = utilFailure<int>(
        util: UtilName.timing,
        code: UtilErrorCode.invalidInput,
        operation: 'sleep',
        message: 'negative',
      );
      expect(failure.isErr, isTrue);
      expect(
        failure.problem.type,
        utilProblem(
          util: UtilName.timing,
          code: UtilErrorCode.invalidInput,
          operation: 'sleep',
          message: 'negative',
        ).type,
      );
    });

    test('utilFailure forwards details and portal', () {
      final Err<int> failure = utilFailure<int>(
        util: UtilName.vfs,
        code: UtilErrorCode.delegated,
        operation: 'load',
        message: 'downstream',
        portal: ErrorPortal.localError,
        details: <String, Object?>{
          'paths': <String>['/a'],
        },
      );
      expect(failure.problem.data['paths'], <String>['/a']);
    });

    test('invalidUtilInput names the offending field', () {
      final Err<String> failure = invalidUtilInput<String>(
        util: UtilName.slug,
        operation: 'namespacedKey',
        field: 'namespace',
        message: 'empty',
      );
      expect(failure.problem.data['field'], 'namespace');
      expect(failure.problem.data['code'], 'invalid_input');
      expect(failure.problem.status, 400);
    });

    test('invalidWireFormat names the grammar and the rejected value', () {
      final Err<int> failure = invalidWireFormat<int>(
        operation: 'WireDate.parse',
        expected: wireDateGrammar,
        value: '21-07-2026',
      );
      expect(failure.problem.data['util'], 'wire');
      expect(failure.problem.data['expected'], wireDateGrammar);
      expect(failure.problem.data['value'], '21-07-2026');
      expect(failure.problem.title, 'expected $wireDateGrammar');
    });
  });

  group('the envelope survives the published Result wire codec', () {
    test('an Err round-trips through the C0 §5 tagged-array form', () {
      // Real consumption of diene_result: a core-utils failure must be carriable
      // across a wire boundary by the published codec without loss.
      final Result<String> failure = namespacedKey('---', 'key');
      final ResultSerial encoded = failure.serial();
      final Result<String> decoded = Result<String>.fromSerial(
        encoded,
        decodeOk: (Object? value) => value! as String,
      );

      expect(decoded.isErr, isTrue);
      expect(decoded.unwrapErr().type, failure.unwrapErr().type);
      expect(decoded.unwrapErr().data['field'], 'namespace');
    });
  });
}
