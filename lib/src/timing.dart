import 'dart:async';

/// Completes after [duration].
Future<void> sleep(Duration duration) {
  if (duration.isNegative) {
    throw ArgumentError.value(duration, 'duration', 'must not be negative');
  }
  return Future<void>.delayed(duration);
}
