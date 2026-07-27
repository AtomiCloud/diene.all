import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Note', () {
    test('exposes its fields, equality, hashCode, and text', () {
      // Arrange
      const Note note = Note(title: 'Release', body: 'Ship the template.');
      const Note same = Note(title: 'Release', body: 'Ship the template.');
      const Note otherTitle = Note(title: 'Draft', body: 'Ship the template.');
      const Note otherBody = Note(title: 'Release', body: 'Hold the template.');

      // Assert
      expect(note.title, 'Release');
      expect(note.body, 'Ship the template.');
      expect(note, same);
      expect(note.hashCode, same.hashCode);
      expect(note == otherTitle, isFalse);
      expect(note == otherBody, isFalse);
      expect(note == Object(), isFalse);
      expect(note.toString(), 'Note(title: Release, body: Ship the template.)');
    });

    test('round-trips through its JSON wire codec', () {
      // Arrange
      const Note note = Note(title: 'Release', body: 'Ship the template.');

      // Act
      final Map<String, Object?> wire = note.toJson();
      final Note decoded = Note.fromJson(wire);

      // Assert
      expect(wire, <String, Object?>{
        'title': 'Release',
        'body': 'Ship the template.',
      });
      expect(decoded, note);
    });

    test('decodes an empty body', () {
      // Act
      final Note decoded = Note.fromJson(<String, Object?>{
        'title': 'Heading',
        'body': '',
      });

      // Assert
      expect(decoded.body, isEmpty);
    });

    test('rejects a missing or non-string title', () {
      // Assert
      expect(
        () => Note.fromJson(<String, Object?>{'title': 42, 'body': 'x'}),
        throwsFormatException,
      );
      expect(
        () => Note.fromJson(<String, Object?>{'title': '', 'body': 'x'}),
        throwsFormatException,
      );
    });

    test('rejects a non-string body', () {
      // Assert
      expect(
        () => Note.fromJson(<String, Object?>{'title': 'ok', 'body': 42}),
        throwsFormatException,
      );
    });
  });
}
