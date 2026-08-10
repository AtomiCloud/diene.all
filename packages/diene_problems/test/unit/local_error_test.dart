import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

final class _RecordingSink implements ErrorSink {
  Problem? captured;

  @override
  Future<void> capture(Problem problem) async => captured = problem;
}

void main() {
  group('LocalError', () {
    test(
      'wraps message + stacktrace into data and routes through the builder',
      () async {
        // Arrange
        const portal = ErrorPortal(
          scheme: 'https',
          host: 'docs.raichu.cluster.atomi.cloud',
          landscape: 'raichu',
          platform: 'dotnet',
          service: 'user',
          module: 'api',
        );
        final sink = _RecordingSink();
        final stack = StackTrace.current;
        // Act
        final problem = await LocalError(
          sink,
          portal: portal,
        ).wrap(StateError('broken'), stack);
        // Assert
        expect(problem.title, 'Local Error');
        expect(problem.status, 500);
        expect(problem.recoverable, false);
        expect(problem.detail, contains('broken'));
        expect(problem.data['message'], contains('broken'));
        expect(problem.data['stackTrace'], stack.toString());
        expect(
          problem.type,
          'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/local_error',
        );
        expect(sink.captured, same(problem));
      },
    );

    test('uses the localError fallback portal by default', () async {
      final problem = await const LocalError(
        NoopErrorSink(),
      ).wrap('x', StackTrace.empty);
      expect(
        problem.type,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
      );
    });
  });

  test('NoopErrorSink captures nothing (no throw)', () async {
    const sink = NoopErrorSink();
    await expectLater(
      sink.capture(const Problem(type: 't', title: 'T', status: 500)),
      completes,
    );
  });
}
