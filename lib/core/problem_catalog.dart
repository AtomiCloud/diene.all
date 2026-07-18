import 'result.dart';

typedef UnexpectedProblemSink = Future<void> Function(Problem problem);

final class ProblemCatalogEntry {
  const ProblemCatalogEntry({
    required this.type,
    required this.title,
    required this.status,
    required this.recoverable,
  });

  final String type;
  final String title;
  final int status;
  final bool recoverable;
}

final class ProblemCatalog {
  ProblemCatalog({required this.endpoints, UnexpectedProblemSink? onUnexpected})
    : _onUnexpected = onUnexpected ?? _ignore;

  final Map<String, Map<int, ProblemCatalogEntry>> endpoints;
  final UnexpectedProblemSink _onUnexpected;

  Future<Problem> classify({
    required String endpoint,
    required int status,
    String? detail,
    String? instance,
  }) async {
    final ProblemCatalogEntry? entry = endpoints[endpoint]?[status];
    if (entry != null) {
      return Problem(
        type: entry.type,
        title: entry.title,
        status: entry.status,
        detail: detail,
        instance: instance,
        recoverable: entry.recoverable,
      );
    }
    final Problem unexpected = Problem(
      type: 'urn:diene:problem:uncatalogued',
      title: 'Unexpected service response',
      status: 500,
      detail: detail,
      instance: instance,
      data: <String, Object?>{'endpoint': endpoint, 'upstreamStatus': status},
    );
    await _onUnexpected(unexpected);
    return unexpected;
  }

  static Future<void> _ignore(Problem problem) async {}
}
