/// The failure value carried by [Result].
///
/// It follows the RFC 9457 envelope and preserves the C0 `data` extension.
/// The downstream `diene_problems` package builds catalogs and typed problem
/// helpers around this dependency-root representation.
final class Problem {
  /// Creates a problem envelope.
  Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    Map<String, Object?> data = const <String, Object?>{},
  }) : data = Map<String, Object?>.unmodifiable(data);

  /// Decodes a strict C0 problem envelope.
  factory Problem.fromJson(Map<String, Object?> json) => Problem(
    type: _requiredString(json, 'type'),
    title: _requiredString(json, 'title'),
    status: _requiredInt(json, 'status'),
    detail: _optionalString(json, 'detail'),
    instance: _optionalString(json, 'instance'),
    recoverable: _optionalBool(json, 'recoverable') ?? false,
    data: _optionalData(json, 'data'),
  );

  /// Decodes a problem from an untyped JSON wire value.
  factory Problem.fromWire(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Problem wire value must be an object.');
    }

    return Problem.fromJson(
      value.map<String, Object?>(
        (Object? key, Object? item) =>
            MapEntry<String, Object?>(key.toString(), item),
      ),
    );
  }

  /// Versioned problem-type URI.
  final String type;

  /// Human-readable problem title.
  final String title;

  /// HTTP-compatible status code.
  final int status;

  /// Optional occurrence-specific detail.
  final String? detail;

  /// Optional occurrence identifier.
  final String? instance;

  /// Catalog classification used by frontend error presentation.
  final bool recoverable;

  /// Typed C0 extension payload.
  final Map<String, Object?> data;

  /// Encodes this envelope as a JSON-compatible map.
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
  String toString() => 'Problem(type: $type, title: $title, status: $status)';
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }

  throw FormatException('Problem.$key must be a non-empty string.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is int) {
    return value;
  }

  throw FormatException('Problem.$key must be an integer.');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }

  throw FormatException('Problem.$key must be a string when present.');
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null || value is bool) {
    return value as bool?;
  }

  throw FormatException('Problem.$key must be a boolean when present.');
}

Map<String, Object?> _optionalData(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Problem.$key must be an object when present.');
  }

  return value.map<String, Object?>(
    (Object? itemKey, Object? item) =>
        MapEntry<String, Object?>(itemKey.toString(), item),
  );
}
