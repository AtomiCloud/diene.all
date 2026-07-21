import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// Identifies the input that made a namespaced key invalid.
enum NamespacedKeyField { namespace, key }

/// Validation detail returned by [namespacedKey].
final class NamespacedKeyValidationError {
  const NamespacedKeyValidationError({
    required this.field,
    required this.reason,
  });

  final NamespacedKeyField field;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is NamespacedKeyValidationError &&
      other.field == field &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(field, reason);

  @override
  String toString() => '${field.name} $reason';
}

/// Non-throwing result of constructing a namespaced key.
sealed class NamespacedKeyResult {
  const NamespacedKeyResult();

  bool get isValid;

  R match<R>({
    required R Function(String value) valid,
    required R Function(NamespacedKeyValidationError error) invalid,
  });
}

/// A validated `namespace:key` value.
final class ValidNamespacedKey extends NamespacedKeyResult {
  const ValidNamespacedKey(this.value);

  final String value;

  @override
  bool get isValid => true;

  @override
  R match<R>({
    required R Function(String value) valid,
    required R Function(NamespacedKeyValidationError error) invalid,
  }) =>
      valid(value);

  @override
  bool operator ==(Object other) =>
      other is ValidNamespacedKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An invalid namespace or key component.
final class InvalidNamespacedKey extends NamespacedKeyResult {
  const InvalidNamespacedKey(this.error);

  final NamespacedKeyValidationError error;

  @override
  bool get isValid => false;

  @override
  R match<R>({
    required R Function(String value) valid,
    required R Function(NamespacedKeyValidationError error) invalid,
  }) =>
      invalid(error);

  @override
  bool operator ==(Object other) =>
      other is InvalidNamespacedKey && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

final RegExp _combiningMarks = RegExp(
  '[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]',
);
final RegExp _notAsciiAlphaNumeric = RegExp('[^a-z0-9]+');
final RegExp _edgeHyphens = RegExp(r'^-+|-+$');

/// Normalizes [input] with NFKD and returns a lowercase ASCII kebab slug.
String slugify(String input) => unicode
    .nfkd(input)
    .replaceAll(_combiningMarks, '')
    .toLowerCase()
    .trim()
    .replaceAll(_notAsciiAlphaNumeric, '-')
    .replaceAll(_edgeHyphens, '');

/// Builds `namespace:key`, returning validation as data instead of throwing.
NamespacedKeyResult namespacedKey(String namespace, String key) {
  final String normalizedNamespace = slugify(namespace);
  if (normalizedNamespace.isEmpty) {
    return const InvalidNamespacedKey(
      NamespacedKeyValidationError(
        field: NamespacedKeyField.namespace,
        reason: 'must not be empty',
      ),
    );
  }

  final String normalizedKey = slugify(key);
  if (normalizedKey.isEmpty) {
    return const InvalidNamespacedKey(
      NamespacedKeyValidationError(
        field: NamespacedKeyField.key,
        reason: 'must not be empty',
      ),
    );
  }

  return ValidNamespacedKey('$normalizedNamespace:$normalizedKey');
}
