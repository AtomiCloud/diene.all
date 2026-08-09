import 'result.dart';

abstract interface class ErrorSink {
  Future<void> capture(Problem problem);
}

final class NoopErrorSink implements ErrorSink {
  const NoopErrorSink();

  @override
  Future<void> capture(Problem problem) async {}
}

final class LocalError {
  const LocalError(this.sink);

  final ErrorSink sink;

  Future<Problem> wrap(Object error, StackTrace stackTrace) async {
    final Problem problem = Problem(
      type: 'urn:diene:problem:local-error',
      title: 'Local Error',
      status: 500,
      detail: error.toString(),
      data: <String, Object?>{
        'message': error.toString(),
        'stackTrace': stackTrace.toString(),
      },
    );
    await sink.capture(problem);
    return problem;
  }
}
