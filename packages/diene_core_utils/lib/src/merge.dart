/// Layered configuration merging over JSON-like values.
library;

/// A JSON-like configuration object.
typedef JsonObject = Map<String, Object?>;

/// Deeply clones a JSON-like value.
///
/// Maps and lists are rebuilt; every other value is a JSON scalar and is
/// returned as-is. The result shares no mutable structure with [value], so a
/// caller may mutate either independently. Cyclic input is out of contract here
/// — use `stableConfig` when the shape is untrusted.
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
/// Map keys match through [canonicalConfigKey], so a `--dart-define` spelled
/// `APP_SETTINGS__DISPLAY_NAME` lands on a YAML key spelled `displayName`
/// (C0 §3 case-insensitive key matching). The FIRST spelling wins as the output
/// key, so the base layer's own naming survives an overlay that spells a key
/// differently. Maps merge recursively; lists and scalars replace wholesale —
/// C0 §3 has no list-append semantics.
JsonObject deepMerge(Map<String, Object?> base, Map<String, Object?> overlay) {
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

/// Deep-merges [layers] from lowest to highest precedence.
///
/// This is the C0 §3 precedence ladder itself: `base -> flavor/landscape
/// overlay -> --dart-define` is just this fold in that order.
JsonObject deepMergeAll(Iterable<Map<String, Object?>> layers) =>
    layers.fold<JsonObject>(<String, Object?>{}, deepMerge);

/// Canonicalises a configuration key for separator- and case-insensitive
/// matching.
///
/// Hyphens and underscores are removed and the remainder is lowercased, so
/// `display-name`, `display_name`, `displayName`, and `DisplayName` all
/// canonicalise to `displayname`.
String canonicalConfigKey(String key) =>
    key.replaceAll(_separators, '').toLowerCase();

/// Whether two configuration keys identify the same logical key.
bool configKeysMatch(String left, String right) =>
    canonicalConfigKey(left) == canonicalConfigKey(right);

final RegExp _separators = RegExp('[-_]');
