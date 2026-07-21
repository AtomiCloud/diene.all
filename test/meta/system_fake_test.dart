import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support/result_expectations.dart';

void main() {
  group('InMemorySystem', () {
    test('returns deterministic state and records delay requests', () async {
      // Arrange.
      final DateTime now = DateTime.utc(2026, 7, 21, 12);
      final InMemorySystem system = InMemorySystem(
        environment: <String, String>{'MODE': 'test'},
        directory: '/workspace',
        now: now,
      );

      // Act.
      final Result<String?> present = system.environment('MODE');
      final Result<String?> absent = system.environment('ABSENT');
      final Result<String> directory = system.currentDirectory();
      final Result<DateTime> clock = system.nowUtc();
      final Result<void> delayed = await system.delay(
        const Duration(seconds: 2),
      );

      // Assert.
      expect(expectSuccess(present), 'test');
      expect(expectSuccess(absent), isNull);
      expect(expectSuccess(directory), '/workspace');
      expect(expectSuccess(clock), now);
      expectSuccess(delayed);
      expect(system.requestedDelays, <Duration>[const Duration(seconds: 2)]);
    });

    test('returns each queued result once before resuming state', () async {
      // Arrange.
      final InMemorySystem system = InMemorySystem();
      final Failure<String?> environmentFailure = failure<String?>(
        'environment',
      );
      final Failure<String> directoryFailure = failure<String>('directory');
      final Failure<DateTime> clockFailure = failure<DateTime>('clock');
      final Failure<void> delayFailure = failure<void>('delay');
      system.enqueueEnvironmentResult(environmentFailure);
      system.enqueueDirectoryResult(directoryFailure);
      system.enqueueClockResult(clockFailure);
      system.enqueueDelayResult(delayFailure);

      // Act.
      final Result<String?> environment = system.environment('MODE');
      final Result<String> directory = system.currentDirectory();
      final Result<DateTime> clock = system.nowUtc();
      final Result<void> delay = await system.delay(Duration.zero);

      // Assert.
      expect(environment, same(environmentFailure));
      expect(directory, same(directoryFailure));
      expect(clock, same(clockFailure));
      expect(delay, same(delayFailure));
      expect(expectSuccess(system.currentDirectory()), '/');
    });
  });
}
