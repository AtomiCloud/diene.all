/// diene_problems — RFC 9457 problem-details machinery for the Dart family.
///
/// Public API surface:
/// - [Problem] envelope (RFC 9457 + `data` + `recoverable`);
/// - [problemTypeUri] / [ErrorPortal] — the ONE type-URI builder (C0 §2);
/// - [ProblemType] / [ProblemRegistry] / [GenericProblems] — typed registry;
/// - [fromObject] / [TransformOptions] — error → Problem transformer;
/// - [LocalError] / [ErrorSink] — unexpected-exception wrapping;
/// - [CatalogEntry] / [CatalogEndpoint] / [ProblemCatalog] — catalog EXPORT
///   (C0 §14), the producer side of the edge error portal.
library;

export 'c0_problem.dart';
export 'src/catalog.dart';
export 'src/local_error.dart';
export 'src/problem.dart';
export 'src/problem_type_uri.dart';
export 'src/registry.dart';
export 'src/transformer.dart';
