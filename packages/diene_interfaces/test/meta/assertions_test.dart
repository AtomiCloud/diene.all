import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

Problem _problem({
  PortName port = PortName.vfs,
  PortErrorCode code = PortErrorCode.notFound,
  String operation = 'readText',
}) =>
    portProblem(port: port, code: code, operation: operation, message: 'boom');

void main() {
  group('expectPortProblem accepts known-good envelopes', () {
    test('matches seam, code, status, recoverable flag, and operation', () {
      // Arrange.
      final Problem problem = _problem();

      // Act.
      final Problem returned = expectPortProblem(
        problem,
        port: PortName.vfs,
        code: PortErrorCode.notFound,
        operation: 'readText',
      );

      // Assert.
      expect(returned, same(problem));
    });

    test('leaves the operation unchecked when none is supplied', () {
      // Arrange & Act & Assert.
      expect(
        expectPortProblem(
          _problem(operation: 'anything'),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
        ),
        isNotNull,
      );
    });

    test('accepts a recoverable code', () {
      // Arrange & Act & Assert.
      expect(
        expectPortProblem(
          _problem(port: PortName.terminal, code: PortErrorCode.timeout),
          port: PortName.terminal,
          code: PortErrorCode.timeout,
        ),
        isNotNull,
      );
    });
  });

  group('expectPortProblem FAILS on known-bad envelopes', () {
    test('rejects a mismatched seam', () {
      // Arrange & Act & Assert.
      expect(
        () => expectPortProblem(
          _problem(),
          port: PortName.system,
          code: PortErrorCode.notFound,
        ),
        throwsA(
          isA<SeamAssertionFailure>().having(
            (SeamAssertionFailure failure) => failure.message,
            'message',
            contains('Expected a system/not-found problem'),
          ),
        ),
      );
    });

    test('rejects a mismatched code', () {
      // Arrange & Act & Assert.
      expect(
        () => expectPortProblem(
          _problem(),
          port: PortName.vfs,
          code: PortErrorCode.io,
        ),
        throwsA(isA<SeamAssertionFailure>()),
      );
    });

    test('rejects a mismatched operation', () {
      // Arrange & Act & Assert.
      expect(
        () => expectPortProblem(
          _problem(),
          port: PortName.vfs,
          code: PortErrorCode.notFound,
          operation: 'writeText',
        ),
        throwsA(
          isA<SeamAssertionFailure>().having(
            (SeamAssertionFailure failure) => failure.message,
            'message',
            contains('Expected operation "writeText"'),
          ),
        ),
      );
    });

    test('rejects an envelope whose status was tampered with', () {
      // Arrange.
      final Problem tampered = Problem(
        type: _problem().type,
        title: 'boom',
        status: 500,
        data: _problem().data,
      );

      // Act & Assert.
      expect(
        () => expectPortProblem(
          tampered,
          port: PortName.vfs,
          code: PortErrorCode.notFound,
        ),
        throwsA(
          isA<SeamAssertionFailure>().having(
            (SeamAssertionFailure failure) => failure.message,
            'message',
            contains('Expected status 404'),
          ),
        ),
      );
    });

    test('rejects an envelope whose recoverable flag was tampered with', () {
      // Arrange.
      final Problem source = _problem(code: PortErrorCode.timeout);
      final Problem tampered = Problem(
        type: source.type,
        title: source.title,
        status: source.status,
        data: source.data,
      );

      // Act & Assert.
      expect(
        () => expectPortProblem(
          tampered,
          port: PortName.vfs,
          code: PortErrorCode.timeout,
        ),
        throwsA(
          isA<SeamAssertionFailure>().having(
            (SeamAssertionFailure failure) => failure.message,
            'message',
            contains('Expected recoverable=true'),
          ),
        ),
      );
    });
  });

  test('SeamAssertionFailure renders its diagnostic', () {
    // Arrange & Act & Assert.
    expect(
      const SeamAssertionFailure('nope').toString(),
      'SeamAssertionFailure: nope',
    );
  });
}
