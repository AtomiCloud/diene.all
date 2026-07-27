import 'package:diene_api_engine/diene_api_engine.dart';

/// Demonstrates the clean consumer path: build a [Note], summarise it, and
/// round-trip it through the JSON wire codec via the public barrel alone.
void main() {
  const Note note = Note(
    title: 'Release',
    body: 'Ship the pure-Dart template.',
  );

  final String summary = summarizeNote(note);
  assert(
    summary == 'Release — Ship the pure-Dart template.',
    'the summariser joins the title and body',
  );

  final Note roundTripped = Note.fromJson(note.toJson());
  assert(roundTripped == note, 'the wire codec round-trips');
}
