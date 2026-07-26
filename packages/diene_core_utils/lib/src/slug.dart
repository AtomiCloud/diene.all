/// Deterministic slug and namespaced-key composition.
library;

import 'package:diene_result/diene_result.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'util_problem.dart';

/// Identifies the input that made a namespaced key invalid.
enum NamespacedKeyField {
  /// The namespace component.
  namespace,

  /// The key component.
  key,
}

// Combining-mark blocks removed after NFKD: Combining Diacritical Marks and its
// Extended, Supplement, Symbols, and Half Marks continuations. Written as escape
// sequences so the source stays ASCII and reviewable.
final RegExp _combiningMarks = RegExp(
  '[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]',
);
final RegExp _notAsciiAlphaNumeric = RegExp('[^a-z0-9]+');
final RegExp _edgeHyphens = RegExp(r'^-+|-+$');

/// Normalises an arbitrary string into a deterministic kebab-case slug.
///
/// The transform is NFKD normalisation, combining-mark removal, lowercasing,
/// trimming, and collapsing every run of non-ASCII-alphanumeric characters into
/// a single hyphen, with leading and trailing hyphens stripped. It is total: an
/// input with no retainable characters slugifies to the empty string rather
/// than failing.
String slugify(String input) => unicode
    .nfkd(input)
    .replaceAll(_combiningMarks, '')
    .toLowerCase()
    .trim()
    .replaceAll(_notAsciiAlphaNumeric, '-')
    .replaceAll(_edgeHyphens, '');

/// Composes a `namespace:key` identifier from slugified parts.
///
/// Both components are put through [slugify] first, so callers may pass raw
/// human text. A component that slugifies to empty carries no identity, so the
/// composition fails as a value with an `invalid_input` [Problem] naming the
/// offending [NamespacedKeyField] — it never throws.
Result<String> namespacedKey(String namespace, String key) {
  final String normalizedNamespace = slugify(namespace);
  if (normalizedNamespace.isEmpty) {
    return invalidUtilInput<String>(
      util: UtilName.slug,
      operation: 'namespacedKey',
      field: NamespacedKeyField.namespace.name,
      message: 'namespace must not slugify to empty',
    );
  }

  final String normalizedKey = slugify(key);
  if (normalizedKey.isEmpty) {
    return invalidUtilInput<String>(
      util: UtilName.slug,
      operation: 'namespacedKey',
      field: NamespacedKeyField.key.name,
      message: 'key must not slugify to empty',
    );
  }

  return Ok<String>('$normalizedNamespace:$normalizedKey');
}
