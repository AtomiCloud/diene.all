import 'package:diene_core_utils/diene_core_utils.dart' as core_utils;

/// Recursively merges [overlay] onto [base].
///
/// Configuration keys match canonically across case, hyphens, and underscores.
/// Maps merge recursively; lists and scalar values replace the previous value.
/// The returned tree does not share mutable maps or lists with either input.
Map<String, Object?> deepMerge(
  Map<String, Object?> base,
  Map<String, Object?> overlay,
) => core_utils.deepMerge(base, overlay);
