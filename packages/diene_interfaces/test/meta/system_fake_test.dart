import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySystem defaults', () {
    test('answers from its seeded environment, directory, and clock', () {
      // Arrange.
      final InMemorySystem system = InMemorySystem(
        environment: <String, String>{'HOME': '/home/dev'},
        directory: '/work',
        now: DateTime.utc(2026, 7, 25, 6, 30),
      );

      // Act.
      final String? home = expectOk(system.environment('HOME'));
      final String? absent = expectOk(system.environment('MISSING'));
      final String directory = expectOk(system.currentDirectory());
      final DateTime now = expectOk(system.nowUtc());

      // Assert.
      expect(home, '/home/dev');
      expect(absent, isNull, reason: 'absence is Ok(null), not a failure');
      expect(directory, '/work');
      expect(now, DateTime.utc(2026, 7, 25, 6, 30));
      expect(now.isUtc, isTrue);
    });

    test('uses the epoch and root when unseeded', () {
      // Arrange & Act.
      final InMemorySystem system = InMemorySystem();

      // Assert.
      expect(expectOk(system.currentDirectory()), '/');
      expect(
        expectOk(system.nowUtc()),
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('normalises a local seed instant to UTC', () {
      // Arrange & Act.
      final InMemorySystem system = InMemorySystem(now: DateTime(2026, 7, 25));

      // Assert.
      expect(expectOk(system.nowUtc()).isUtc, isTrue);
    });

    test('records every requested delay and succeeds by default', () async {
      // Arrange.
      final InMemorySystem system = InMemorySystem();

      // Act.
      expectOk(await system.delay(const Duration(milliseconds: 5)));
      expectOk(await system.delay(const Duration(seconds: 1)));

      // Assert.
      expect(system.requestedDelays, <Duration>[
        const Duration(milliseconds: 5),
        const Duration(seconds: 1),
      ]);
    });

    test('exposes its environment and directory as mutable seams', () {
      // Arrange.
      final InMemorySystem system = InMemorySystem();

      // Act.
      system.environmentVariables['ADDED'] = 'yes';
      system.directory = '/moved';
      system.now = DateTime.utc(2030);

      // Assert.
      expect(expectOk(system.environment('ADDED')), 'yes');
      expect(expectOk(system.currentDirectory()), '/moved');
      expect(expectOk(system.nowUtc()), DateTime.utc(2030));
    });
  });

  group('InMemorySystem scripted results', () {
    test('serves scripted answers FIFO, then falls back to state', () {
      // Arrange.
      final InMemorySystem system = InMemorySystem(
        environment: <String, String>{'HOME': '/fallback'},
      )..enqueueEnvironmentResult(const Ok<String?>('/scripted'));
      system.enqueueEnvironmentResult(
        portFailure<String?>(
          port: PortName.system,
          code: PortErrorCode.permissionDenied,
          operation: 'environment',
          message: 'Environment unreadable',
        ),
      );

      // Act.
      final String? first = expectOk(system.environment('HOME'));
      final Object second = expectErr(system.environment('HOME'));
      final String? third = expectOk(system.environment('HOME'));

      // Assert.
      expect(first, '/scripted');
      expect(second, isNotNull);
      expect(third, '/fallback');
    });

    test('scripts directory, clock, and delay failures', () async {
      // Arrange.
      final InMemorySystem system = InMemorySystem()
        ..enqueueDirectoryResult(
          portFailure<String>(
            port: PortName.system,
            code: PortErrorCode.io,
            operation: 'currentDirectory',
            message: 'Directory unavailable',
          ),
        )
        ..enqueueClockResult(
          portFailure<DateTime>(
            port: PortName.system,
            code: PortErrorCode.unavailable,
            operation: 'nowUtc',
            message: 'Clock unavailable',
          ),
        )
        ..enqueueDelayResult(
          portFailure<void>(
            port: PortName.system,
            code: PortErrorCode.timeout,
            operation: 'delay',
            message: 'Timer failed',
          ),
        );

      // Act & Assert.
      expectPortProblem(
        expectErr(system.currentDirectory()),
        port: PortName.system,
        code: PortErrorCode.io,
      );
      expectPortProblem(
        expectErr(system.nowUtc()),
        port: PortName.system,
        code: PortErrorCode.unavailable,
      );
      expectPortProblem(
        expectErr(await system.delay(Duration.zero)),
        port: PortName.system,
        code: PortErrorCode.timeout,
      );
      expect(system.requestedDelays, hasLength(1));
    });
  });
}
