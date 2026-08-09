import 'note.dart';

/// The default maximum length of a rendered [Note] summary.
const int defaultSummaryLength = 80;

/// Produces a single-line summary of [note], capped at [maxLength] characters.
///
/// The title and a non-empty body are joined with an em dash and internal
/// whitespace is collapsed to single spaces. When the collapsed text exceeds
/// [maxLength] it is hard-truncated and suffixed with an ellipsis.
///
/// Throws an [ArgumentError] when [maxLength] is not positive.
String summarizeNote(Note note, {int maxLength = defaultSummaryLength}) {
  if (maxLength <= 0) {
    throw ArgumentError.value(maxLength, 'maxLength', 'must be positive');
  }
  final String combined = note.body.isEmpty
      ? note.title
      : '${note.title} — ${note.body}';
  final String collapsed = combined.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return '${collapsed.substring(0, maxLength).trimRight()}…';
}
