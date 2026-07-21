/// A JSON-like configuration object.
typedef JsonObject = Map<String, Object?>;

/// Deeply clones a JSON-like value.
Object? deepClone(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in value.entries)
        entry.key: deepClone(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) deepClone(item)];
  }
  return value;
}

/// Deep-merges [overlay] over [base] without mutating either input.
///
/// Map keys match case-insensitively across snake, kebab, camel, and Pascal
/// spellings. Maps merge recursively; lists and scalar values replace.
JsonObject deepMerge(
  Map<String, Object?> base,
  Map<String, Object?> overlay,
) {
  final JsonObject result = deepClone(base)! as JsonObject;
  final Map<String, String> existingKeys = <String, String>{
    for (final String key in result.keys) canonicalConfigKey(key): key,
  };

  for (final MapEntry<String, Object?> entry in overlay.entries) {
    final String canonical = canonicalConfigKey(entry.key);
    final String targetKey = existingKeys[canonical] ?? entry.key;
    final Object? current = result[targetKey];
    final Object? incoming = entry.value;

    if (current is Map<String, Object?> && incoming is Map<String, Object?>) {
      result[targetKey] = deepMerge(current, incoming);
    } else {
      result[targetKey] = deepClone(incoming);
    }
    existingKeys[canonical] = targetKey;
  }

  return result;
}

/// Deep-merges [layers] from first to last.
JsonObject deepMergeAll(Iterable<Map<String, Object?>> layers) =>
    layers.fold<JsonObject>(<String, Object?>{}, deepMerge);

/// Canonicalizes a configuration key for separator-insensitive matching.
String canonicalConfigKey(String key) =>
    key.replaceAll(RegExp('[-_]'), '').toLowerCase();

/// Whether two configuration keys identify the same logical key.
bool configKeysMatch(String left, String right) =>
    canonicalConfigKey(left) == canonicalConfigKey(right);
