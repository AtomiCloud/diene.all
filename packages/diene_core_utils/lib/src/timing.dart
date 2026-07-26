/// Duration-based waiting.
library;

import 'dart:async';

import 'package:diene_result/diene_result.dart';

import 'util_problem.dart';

/// Completes after [duration] has elapsed.
///
/// A negative duration cannot be waited out, so it is reported as an
/// `invalid_input` [Problem] and no timer is scheduled — the failure is a value,
/// never a thrown `ArgumentError`. `Duration.zero` is valid and yields to the
/// event loop once.
Future<Result<void>> sleep(Duration duration) async {
  if (duration.isNegative) {
    return invalidUtilInput<void>(
      util: UtilName.timing,
      operation: 'sleep',
      field: 'duration',
      message: 'duration must not be negative',
    );
  }
  await Future<void>.delayed(duration);
  return const Ok<void>(null);
}
