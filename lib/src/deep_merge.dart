/// Recursively merges [overlay] onto [base].
///
/// Maps merge recursively. Lists and scalar values replace the value from the
/// previous layer. The returned tree does not share mutable maps or lists with
/// either input.
Map<String, Object?> deepMerge(
  Map<String, Object?> base,
  Map<String, Object?> overlay,
) {
  final Map<String, Object?> result = _copyMap(base);
  for (final MapEntry<String, Object?> entry in overlay.entries) {
    final Object? existing = result[entry.key];
    final Object? incoming = entry.value;
    if (existing is Map<String, Object?> && incoming is Map<String, Object?>) {
      result[entry.key] = deepMerge(existing, incoming);
    } else {
      result[entry.key] = _copyValue(incoming);
    }
  }
  return result;
}

Map<String, Object?> _copyMap(Map<String, Object?> value) => value.map(
  (String key, Object? item) =>
      MapEntry<String, Object?>(key, _copyValue(item)),
);

Object? _copyValue(Object? value) => switch (value) {
  final Map<String, Object?> map => _copyMap(map),
  final List<Object?> list => list.map(_copyValue).toList(growable: true),
  _ => value,
};
