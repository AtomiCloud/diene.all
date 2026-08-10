/// RFC 9457 problem-details envelope + `data` extension (C0 §2).
///
/// The envelope carries the standard RFC 9457 members (`type`, `title`,
/// `status`, `detail`, `instance`) plus two Atomi extensions:
/// - [data] — the typed payload member (the schema is published per problem in
///   the catalog, C0 §14);
/// - [recoverable] — the recoverable-vs-fatal flag the frontend classifier
///   splits on (C0 §2/§14), read from the edge-published catalog.
///
/// `type` is ALWAYS a URI minted by the single-source builder
/// (`problemTypeUri`, see `problem_type_uri.dart`); this class never formats
/// the template itself.
library;

import 'dart:convert';

/// A problem-details envelope (RFC 9457 + `data` + `recoverable`).
final class Problem {
  /// Creates a problem envelope.
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    this.data = const <String, Object?>{},
  });

  /// Parses a problem envelope from its JSON object form.
  factory Problem.fromJson(Map<String, Object?> json) {
    final Object? rawData = json['data'];
    final Map<String, Object?> data = rawData is Map<Object?, Object?>
        ? rawData.map(
            (Object? key, Object? value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    return Problem(
      type: json['type'] as String? ?? 'about:blank',
      title: json['title'] as String? ?? 'Unexpected problem',
      status: (json['status'] as num?)?.toInt() ?? 500,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      recoverable: json['recoverable'] as bool? ?? false,
      data: data,
    );
  }

  /// RFC 9457 `type` — a URI identifying the problem type.
  final String type;

  /// RFC 9457 `title` — short, human-readable summary.
  final String title;

  /// RFC 9457 `status` — the HTTP status code (origin-generated).
  final int status;

  /// RFC 9457 `detail` — human-readable explanation specific to this occurrence.
  final String? detail;

  /// RFC 9457 `instance` — URI identifying the specific occurrence.
  final String? instance;

  /// Extension: whether the frontend may offer a retry (C0 §2/§14).
  final bool recoverable;

  /// Extension: typed payload (schema published per problem in the catalog).
  final Map<String, Object?> data;

  /// Serializes the envelope to its JSON object form.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    if (detail != null) 'detail': detail,
    if (instance != null) 'instance': instance,
    'recoverable': recoverable,
    'data': data,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Problem && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'Problem($type, $status, $title)';
}

/// The type URI carried by an unexpected/uncatalogued problem (C0 §14
/// uncatalogued ⇒ 5xx ⇒ catalog-loop rule). Used as the fallback `type` when a
/// concrete registry entry is not (yet) known.
const String uncataloguedProblemId = 'uncatalogued';
