// Production dead-code root for the published diene_api_engine surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the
// public barrel (diene_api_engine.dart) as an entrypoint and incorrectly reports
// the test_helper.dart public functions as unused. Referencing every public
// export here keeps the production-only dead-code pass honest without any
// exclusion list. deadcode.sh copies this file to bin/main.dart inside the
// production-only sandbox, so it lives in the member package where
// `package:diene_api_engine` resolves cleanly (and is excluded from the published
// archive by .pubignore).
import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';

void main() {
  const Note note = Note(
    title: 'Dead-code entrypoint',
    body: 'reference the public surface',
  );

  final Note roundTripped = Note.fromJson(note.toJson());
  final String summary = summarizeNote(
    roundTripped,
    maxLength: defaultSummaryLength,
  );

  // Accept a known-good rendering through the shipped TestHelper...
  assertNoteSummary(roundTripped, summary, maxLength: defaultSummaryLength);

  // ...and prove the failure type is reachable by rejecting a known-bad one.
  try {
    assertNoteSummary(roundTripped, 'wrong');
  } on NoteAssertionFailure catch (error) {
    if (error.message.isEmpty) rethrow;
  }
}
