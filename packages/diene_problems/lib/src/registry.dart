/// Typed problem registry — the enumerable source for catalog export (C0 §2/§14).
///
/// A [ProblemType] declares a versioned problem contract: id, title, version,
/// optional default status, the recoverable flag, and the JSON Schema of its
/// `data` extension. The registry resolves each type's RFC 9457 `type` URI
/// through the single-source builder ([problemTypeUri]), so the catalog and any
/// runtime envelope share one identity for the same problem.
///
/// Domain catalogs live in consumer services; this registry ships only the
/// portable generic set (see [GenericProblems]).
library;

import 'problem_type_uri.dart';

/// A versioned problem-type declaration.
///
/// `version` is part of the contract identity (C0 §2): bumping it mints a NEW
/// problem type URI rather than mutating an existing one.
final class ProblemType {
  /// Creates a problem-type declaration.
  const ProblemType({
    required this.id,
    required this.title,
    required this.version,
    this.status,
    this.recoverable = false,
    this.dataSchema = const <String, Object?>{},
  });

  /// Stable identifier, e.g. `entity_not_found`.
  final String id;

  /// Short human-readable title.
  final String title;

  /// Contract version segment, e.g. `v1`.
  final String version;

  /// Default HTTP status hint for this problem type.
  final int? status;

  /// Whether the frontend may offer a retry (C0 §2/§14).
  final bool recoverable;

  /// JSON Schema describing the `data` extension payload.
  final Map<String, Object?> dataSchema;
}

/// Thrown when registering a duplicate problem id.
class DuplicateProblemTypeError extends StateError {
  DuplicateProblemTypeError(String id)
    : super('problem type already registered: $id');
}

/// Thrown when resolving an unknown problem id.
class UnknownProblemTypeError extends StateError {
  UnknownProblemTypeError(String id)
    : super('no problem type registered for id: $id');
}

/// An enumerable registry of [ProblemType]s bound to an [ErrorPortal].
///
/// The portal supplies the LPSM segments every type URI is built from, so a
/// registry is the per-service×landscape source of truth the catalog emitter
/// renders into `Problem` CR content (C0 §14).
final class ProblemRegistry {
  /// Creates a registry bound to [portal], optionally pre-populated with [types].
  ProblemRegistry(this.portal, [Iterable<ProblemType>? types])
    : _types = <String, ProblemType>{} {
    if (types != null) {
      for (final ProblemType type in types) {
        register(type);
      }
    }
  }

  /// The error-portal config block every type URI is built from.
  final ErrorPortal portal;

  final Map<String, ProblemType> _types;

  /// Registers [type]; rejects duplicates by id.
  void register(ProblemType type) {
    if (_types.containsKey(type.id)) {
      throw DuplicateProblemTypeError(type.id);
    }
    _types[type.id] = type;
  }

  /// Looks up a type by id, or `null` when absent.
  ProblemType? lookup(String id) => _types[id];

  /// Resolves a type by id; throws [UnknownProblemTypeError] when absent.
  ProblemType require(String id) {
    final ProblemType? type = _types[id];
    if (type == null) {
      throw UnknownProblemTypeError(id);
    }
    return type;
  }

  /// The registered types in insertion order.
  Iterable<ProblemType> get entries => _types.values;

  /// Builds the RFC 9457 `type` URI for [type] via the single-source builder.
  String typeUriFor(ProblemType type) =>
      problemTypeUri(portal: portal, version: type.version, id: type.id);
}

/// Portable generic problem catalog (C0 §2 baseline set).
///
/// These are the versioned generics every service inherits: ValidationError,
/// EntityNotFound, Conflict, Unauthorized, Unauthenticated, InvalidJson. Domain
/// problems stay in consumer services and are never registered here.
abstract final class GenericProblems {
  GenericProblems._();

  /// `400` — request body failed validation.
  static const ProblemType validationError = ProblemType(
    id: 'validation_error',
    title: 'Validation error',
    version: 'v1',
    status: 400,
    recoverable: true,
    dataSchema: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'fields': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'path': <String, Object?>{'type': 'string'},
              'message': <String, Object?>{'type': 'string'},
            },
            'required': <String>['path', 'message'],
          },
        },
      },
      'required': <String>['fields'],
    },
  );

  /// `404` — referenced entity does not exist.
  static const ProblemType entityNotFound = ProblemType(
    id: 'entity_not_found',
    title: 'Entity not found',
    version: 'v1',
    status: 404,
    recoverable: false,
    dataSchema: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'resource': <String, Object?>{'type': 'string'},
        'id': <String, Object?>{},
      },
      'required': <String>['resource'],
    },
  );

  /// `409` — state conflict (duplicate, stale version, …).
  static const ProblemType conflict = ProblemType(
    id: 'conflict',
    title: 'Conflict',
    version: 'v1',
    status: 409,
    recoverable: true,
    dataSchema: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'resource': <String, Object?>{'type': 'string'},
      },
    },
  );

  /// `401` — authenticated identity is missing or invalid.
  static const ProblemType unauthenticated = ProblemType(
    id: 'unauthenticated',
    title: 'Unauthenticated',
    version: 'v1',
    status: 401,
    recoverable: true,
  );

  /// `403` — identity is authenticated but lacks permission.
  static const ProblemType unauthorized = ProblemType(
    id: 'unauthorized',
    title: 'Unauthorized',
    version: 'v1',
    status: 403,
    recoverable: false,
  );

  /// `400` — request body was not valid JSON.
  static const ProblemType invalidJson = ProblemType(
    id: 'invalid_json',
    title: 'Invalid JSON',
    version: 'v1',
    status: 400,
    recoverable: true,
  );

  /// The full baseline set, in stable order.
  static const List<ProblemType> all = <ProblemType>[
    validationError,
    entityNotFound,
    conflict,
    unauthenticated,
    unauthorized,
    invalidJson,
  ];

  /// Registers the baseline set on [registry].
  static void registerAll(ProblemRegistry registry) {
    for (final ProblemType type in all) {
      registry.register(type);
    }
  }
}
