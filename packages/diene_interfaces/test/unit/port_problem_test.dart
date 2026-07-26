import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('PortErrorCode', () {
    test('every code carries a snake_case wire id and an HTTP status', () {
      // Arrange & Act.
      final Iterable<String> ids = PortErrorCode.values.map(
        (PortErrorCode code) => code.wireId,
      );

      // Assert.
      expect(ids.toSet(), hasLength(PortErrorCode.values.length));
      for (final PortErrorCode code in PortErrorCode.values) {
        expect(
          problemWireIdPattern.hasMatch(code.wireId),
          isTrue,
          reason: code.wireId,
        );
        expect(code.status, inInclusiveRange(400, 599));
      }
    });

    test('only transient codes are recoverable', () {
      // Arrange & Act.
      final Set<PortErrorCode> recoverable = PortErrorCode.values
          .where((PortErrorCode code) => code.recoverable)
          .toSet();

      // Assert.
      expect(recoverable, <PortErrorCode>{
        PortErrorCode.timeout,
        PortErrorCode.unavailable,
      });
    });
  });

  group('portProblem', () {
    test('mints the envelope from the code and the seam', () {
      // Arrange & Act.
      final Problem problem = portProblem(
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'readText',
        message: 'Path not found',
        details: <String, Object?>{'path': '/missing'},
      );

      // Assert.
      expect(problem.status, 404);
      expect(problem.title, 'Path not found');
      expect(problem.detail, 'vfs.readText: Path not found');
      expect(problem.recoverable, isFalse);
      expect(problem.data, <String, Object?>{
        'port': 'vfs',
        'code': 'not_found',
        'operation': 'readText',
        'path': '/missing',
      });
    });

    test('honours an injected error portal', () {
      // Arrange.
      const ErrorPortal portal = ErrorPortal(
        scheme: 'https',
        host: 'docs.raichu.cluster.atomi.cloud',
        landscape: 'raichu',
        platform: 'dart',
        service: 'wallet',
        module: 'app',
      );

      // Act.
      final Problem problem = portProblem(
        port: PortName.system,
        code: PortErrorCode.io,
        operation: 'nowUtc',
        message: 'Clock unavailable',
        portal: portal,
      );

      // Assert.
      expect(
        problem.type,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dart/wallet/app'
        '/v1/system_io',
      );
    });

    test('defaults to the client-local portal', () {
      // Arrange & Act.
      final Problem problem = portProblem(
        port: PortName.terminal,
        code: PortErrorCode.unsupported,
        operation: 'readLine',
        message: 'Not interactive',
      );

      // Assert.
      expect(problem.type, startsWith('https://local.atomi.cloud/docs/local/'));
      expect(problem.status, 501);
    });
  });

  group('portFailure and invalidInput', () {
    test('portFailure wraps the envelope in an Err', () {
      // Arrange & Act.
      final Err<int> failure = portFailure<int>(
        port: PortName.metrics,
        code: PortErrorCode.closed,
        operation: 'flush',
        message: 'Collector closed',
      );

      // Assert.
      expect(failure.problem.status, 409);
      expect(expectErr(failure).data['code'], 'closed');
    });

    test('invalidInput names the offending field', () {
      // Arrange & Act.
      final Err<String> failure = invalidInput<String>(
        port: PortName.logging,
        operation: 'emit',
        field: 'message',
        message: 'Log message must be non-blank',
      );

      // Assert.
      expect(failure.problem.status, 400);
      expect(failure.problem.data['field'], 'message');
      expect(failure.problem.data['code'], 'invalid_input');
    });
  });
}
