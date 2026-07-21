import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:test/test.dart';

void main() {
  test('sleep returns a future that completes after a non-negative duration',
      () async {
    // Arrange
    final Stopwatch stopwatch = Stopwatch()..start();

    // Act
    await sleep(Duration.zero);
    stopwatch.stop();

    // Assert
    expect(stopwatch.elapsedMicroseconds, isNonNegative);
  });

  test('sleep rejects negative durations before scheduling', () {
    // Arrange
    const Duration duration = Duration(microseconds: -1);

    // Act
    Future<void> action() => sleep(duration);

    // Assert
    expect(action, throwsArgumentError);
  });
}
