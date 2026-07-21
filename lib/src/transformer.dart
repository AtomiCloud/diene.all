/// Error → Problem transformer (C0 §2).
///
/// Folds an arbitrary thrown/returned value into a typed [Problem]. The HTTP →
/// Result/Problem bridge (`fromHttpError`) lives in `diene_api_engine`, not
/// here; this lib owns only the generic object → envelope fold used everywhere
/// a Dart value needs to become a Problem.
library;

import 'problem.dart';
import 'problem_type_uri.dart';
import 'registry.dart';

/// Options for folding an unknown value into a [Problem].
final class TransformOptions {
  /// Creates transform options.
  const TransformOptions({
    this.portal = ErrorPortal.localError,
    this.registry,
    this.defaultStatus = 500,
    this.defaultVersion = 'v1',
  });

  /// Portal used to build fallback type URIs.
  final ErrorPortal portal;

  /// Registry consulted when the value carries a known problem id; may be null.
  final ProblemRegistry? registry;

  /// Status for an uncatalogued fallback problem.
  final int defaultStatus;

  /// Version segment for fallback type URIs.
  final String defaultVersion;
}

/// Folds [error] into a typed [Problem].
///
/// - If [error] is already a [Problem], it is returned unchanged.
/// - If [options.registry] recognises an id carried on the value (a `problemId`
///   field on a Map, or a `problemId` getter), the registry's type/title/
///   recoverable are used and the `data` payload is preserved.
/// - Otherwise an uncatalogued problem (C0 §14) is produced: `type` built from
///   [TransformOptions.portal] with id [uncataloguedProblemId].
///
/// This never throws: the whole point is to guarantee a Problem for any value.
Problem fromObject(
  Object? error, {
  TransformOptions options = const TransformOptions(),
}) {
  if (error is Problem) {
    return error;
  }

  final ProblemRegistry? registry = options.registry;
  final String? id = _readProblemId(error);
  if (registry != null && id != null) {
    final ProblemType? type = registry.lookup(id);
    if (type != null) {
      return Problem(
        type: registry.typeUriFor(type),
        title: type.title,
        status: type.status ?? options.defaultStatus,
        recoverable: type.recoverable,
        data: _readData(error),
      );
    }
  }

  return Problem(
    type: problemTypeUri(
      portal: options.portal,
      version: options.defaultVersion,
      id: uncataloguedProblemId,
    ),
    title: 'Unexpected problem',
    status: options.defaultStatus,
    detail: error?.toString(),
    recoverable: false,
    data: const <String, Object?>{},
  );
}

String? _readProblemId(Object? error) {
  if (error is Map<String, Object?>) {
    final Object? id = error['problemId'];
    return id is String ? id : null;
  }
  // Ignore dynamic getters (avoid_dynamic_calls lint): only structured Maps
  // carry a declared problem id.
  return null;
}

Map<String, Object?> _readData(Object? error) {
  if (error is Map<String, Object?>) {
    final Object? data = error['data'];
    if (data is Map<Object?, Object?>) {
      return data.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
  }
  return const <String, Object?>{};
}
