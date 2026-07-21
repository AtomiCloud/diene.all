// RFC 9457 problem envelope.
//
// DEPENDENCY STACKING: this is the self-carried subset of the `diene_problems`
// contract that `diene_auth_engine` needs to stand alone in its isolated lane.
// When the conductor stacks the Dart family, this file is deleted and every
// import is repointed at `package:diene_problems/diene_problems.dart`; the
// public shape here is deliberately a strict subset of that surface so the swap
// is mechanical. See docs/standards/auth/index.md § "Dependency stacking".

import 'package:meta/meta.dart';

/// An RFC 9457 problem detail, extended with the family `recoverable` flag and
/// a free-form `data` extension bag.
@immutable
class Problem {
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    this.data = const <String, Object?>{},
  });

  /// Rebuilds a [Problem] from its wire JSON form.
  factory Problem.fromJson(Map<String, Object?> json) => Problem(
    type: json['type'] as String? ?? 'about:blank',
    title: json['title'] as String? ?? 'Unexpected problem',
    status: json['status'] as int? ?? 500,
    detail: json['detail'] as String?,
    instance: json['instance'] as String?,
    recoverable: json['recoverable'] as bool? ?? false,
    data: (json['data'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
        .map((Object? key, Object? value) => MapEntry(key.toString(), value)),
  );

  /// The RFC 9457 `type` URI. Built in exactly one place per C0 §2.
  final String type;

  /// A short, human-readable summary of the problem.
  final String title;

  /// The HTTP-equivalent status code.
  final int status;

  /// A human-readable explanation specific to this occurrence.
  final String? detail;

  /// A URI reference identifying the specific occurrence.
  final String? instance;

  /// Family extension: whether the frontend classifier treats this as
  /// recoverable (retry/continue) rather than fatal.
  final bool recoverable;

  /// The RFC 9457 `data` extension bag.
  final Map<String, Object?> data;

  /// Serializes to the C0 wire form.
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
      other is Problem &&
      other.type == type &&
      other.title == title &&
      other.status == status &&
      other.detail == detail &&
      other.instance == instance &&
      other.recoverable == recoverable;

  @override
  int get hashCode =>
      Object.hash(type, title, status, detail, instance, recoverable);

  @override
  String toString() => 'Problem($status $type: $title)';
}

/// Builds the RFC 9457 `type` URI in exactly ONE place (C0 §2 template):
/// `{base}/{landscape}/{platform}/{service}/{module}/{version}/{id}`.
String problemTypeUri({
  required String base,
  required String landscape,
  required String platform,
  required String service,
  required String module,
  required String version,
  required String id,
}) {
  final String root = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return '$root/$landscape/$platform/$service/$module/$version/$id';
}
