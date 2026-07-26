/// TestHelper for diene_problems — dependency-light sub-library.
///
/// Import via `package:diene_problems/test_helper.dart`. It is framework-free:
/// every helper throws a plain [ProblemMatcherError] (an [AssertionError]) on
/// mismatch, so it works from `package:test`, `flutter_test`, or any other
/// runner without adding a test-framework dependency to a consumer's prod graph.
///
/// Ships:
/// - [expectProblem] — plain-throw matcher over the envelope fields;
/// - [aProblem] / [anErrorPortal] / [aCatalogEntry] — registry-aware builders
///   that mint valid instances so consumer tests stop hand-rolling URIs.
library;

import 'package:diene_problems/diene_problems.dart';

/// Thrown by [expectProblem] when an assertion fails.
///
/// Extends [AssertionError] so any test framework reports it as a failure.
final class ProblemMatcherError extends AssertionError {
  ProblemMatcherError(super.message);
}

Never _fail(String message) => throw ProblemMatcherError(message);

void _check(bool ok, String message) {
  if (!ok) {
    _fail(message);
  }
}

/// Asserts the [actual] envelope matches the expected fields.
///
/// Every argument is optional; only the fields passed are checked. A `null`
/// actual always fails. The matcher deliberately validates each field
/// independently so the failure message names the first mismatched field.
void expectProblem(
  Object? actual, {
  String? type,
  String? title,
  int? status,
  bool? recoverable,
  String? detail,
  String? instance,
  Map<String, Object?>? data,
}) {
  if (actual is! Problem) {
    _fail('expected a Problem but got ${actual.runtimeType}');
  }
  final Problem problem = actual;
  if (type != null) {
    _check(
      problem.type == type,
      'Problem.type mismatch: expected <$type> got <${problem.type}>',
    );
  }
  if (title != null) {
    _check(
      problem.title == title,
      'Problem.title mismatch: expected <$title> got <${problem.title}>',
    );
  }
  if (status != null) {
    _check(
      problem.status == status,
      'Problem.status mismatch: expected <$status> got <${problem.status}>',
    );
  }
  if (recoverable != null) {
    _check(
      problem.recoverable == recoverable,
      'Problem.recoverable mismatch: expected <$recoverable> got <${problem.recoverable}>',
    );
  }
  if (detail != null) {
    _check(
      problem.detail == detail,
      'Problem.detail mismatch: expected <$detail> got <${problem.detail}>',
    );
  }
  if (instance != null) {
    _check(
      problem.instance == instance,
      'Problem.instance mismatch: expected <$instance> got <${problem.instance}>',
    );
  }
  if (data != null) {
    _check(
      _mapsEqual(problem.data, data),
      'Problem.data mismatch: expected <$data> got <${problem.data}>',
    );
  }
}

bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, Object?> entry in a.entries) {
    final Object? other = b[entry.key];
    final Object? value = entry.value;
    if (other is Map<String, Object?> && value is Map<String, Object?>) {
      if (!_mapsEqual(value, other)) {
        return false;
      }
    } else if (other is List<Object?> && value is List<Object?>) {
      if (!_listsEqual(value, other)) {
        return false;
      }
    } else if (other != value) {
      return false;
    }
  }
  return true;
}

bool _listsEqual(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    final Object? av = a[i];
    final Object? bv = b[i];
    if (av is Map<String, Object?> && bv is Map<String, Object?>) {
      if (!_mapsEqual(av, bv)) {
        return false;
      }
    } else if (av is List<Object?> && bv is List<Object?>) {
      if (!_listsEqual(av, bv)) {
        return false;
      }
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}

/// Builds a valid [Problem], defaulting to a single-source type URI.
///
/// When [type] is omitted, the URI is minted by [problemTypeUri] so test
/// problems never hand-format the template either.
Problem aProblem({
  ErrorPortal portal = ErrorPortal.localError,
  String id = 'entity_not_found',
  String version = 'v1',
  String title = 'Entity not found',
  int status = 404,
  bool recoverable = false,
  String? detail,
  String? instance,
  Map<String, Object?> data = const <String, Object?>{},
}) {
  return Problem(
    type: problemTypeUri(portal: portal, version: version, id: id),
    title: title,
    status: status,
    detail: detail,
    instance: instance,
    recoverable: recoverable,
    data: data,
  );
}

/// Builds an [ErrorPortal] for tests, defaulting to a stable, realistic shape.
ErrorPortal anErrorPortal({
  String scheme = 'https',
  String host = 'docs.raichu.cluster.atomi.cloud',
  String landscape = 'raichu',
  String platform = 'dotnet',
  String service = 'user',
  String module = 'api',
}) {
  return ErrorPortal(
    scheme: scheme,
    host: host,
    landscape: landscape,
    platform: platform,
    service: service,
    module: module,
  );
}

/// Builds a [CatalogEntry] whose type URI is minted by the single-source
/// builder, so catalog fixtures stay consistent with the runtime registry.
CatalogEntry aCatalogEntry({
  ErrorPortal portal = ErrorPortal.localError,
  required String id,
  String version = 'v1',
  String title = 'Entity not found',
  int status = 404,
  bool recoverable = false,
  Map<String, Object?> dataSchema = const <String, Object?>{},
  List<CatalogEndpoint> endpoints = const <CatalogEndpoint>[],
}) {
  return CatalogEntry(
    id: id,
    typeUri: problemTypeUri(portal: portal, version: version, id: id),
    title: title,
    status: status,
    recoverable: recoverable,
    dataSchema: dataSchema,
    endpoints: endpoints,
  );
}
