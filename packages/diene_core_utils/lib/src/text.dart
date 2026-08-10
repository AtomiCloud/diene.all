/// Small total text predicates.
library;

/// Case-insensitive substring test.
///
/// Returns `true` when [needle] appears anywhere within [haystack], ignoring
/// letter case. An empty needle is always contained. Case folding uses
/// [String.toLowerCase], which is locale-independent in Dart, so the result is
/// deterministic across hosts.
bool fuzzyIncludes(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());
