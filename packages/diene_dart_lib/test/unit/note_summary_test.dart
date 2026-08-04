import 'package:diene_dart_lib/diene_dart_lib.dart';
import 'package:test/test.dart';

void main() {
  group('summarizeNote', () {
    test('joins the title and body with an em dash', () {
      // Arrange
      const Note note = Note(title: 'Release', body: 'Ship the template.');

      // Act
      final String summary = summarizeNote(note);

      // Assert
      expect(summary, 'Release — Ship the template.');
    });

    test('uses the title alone when the body is empty', () {
      // Arrange
      const Note note = Note(title: 'Heading', body: '');

      // Act
      final String summary = summarizeNote(note);

      // Assert
      expect(summary, 'Heading');
    });

    test('collapses internal whitespace', () {
      // Arrange
      const Note note = Note(title: 'A\tB', body: 'c   d\ne');

      // Act
      final String summary = summarizeNote(note);

      // Assert
      expect(summary, 'A B — c d e');
    });

    test('truncates and adds an ellipsis beyond the maximum length', () {
      // Arrange
      const Note note = Note(title: 'Title', body: 'wording');

      // Act
      final String summary = summarizeNote(note, maxLength: 8);

      // Assert — the cut lands on a space that trimRight removes.
      expect(summary, 'Title —…');
      expect(summary.runes.length, lessThanOrEqualTo(9));
    });

    test('returns the whole text when it fits exactly', () {
      // Arrange
      const Note note = Note(title: 'ab', body: 'cd');

      // Act
      final String summary = summarizeNote(note, maxLength: 7);

      // Assert
      expect(summary, 'ab — cd');
    });

    test('rejects a non-positive maximum length', () {
      // Arrange
      const Note note = Note(title: 'Title', body: 'Body');

      // Assert
      expect(
        () => summarizeNote(note, maxLength: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
