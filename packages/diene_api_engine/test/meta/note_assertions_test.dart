import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

void main() {
  const Note note = Note(title: 'Release', body: 'Ship the template.');

  group('assertNoteSummary', () {
    test('accepts a known-good summary', () {
      // Assert
      expect(
        () => assertNoteSummary(note, 'Release — Ship the template.'),
        returnsNormally,
      );
    });

    test('rejects a known-bad summary with a diagnostic', () {
      // Assert
      expect(
        () => assertNoteSummary(note, 'wrong'),
        throwsA(
          isA<NoteAssertionFailure>()
              .having(
                (NoteAssertionFailure error) => error,
                'is a StateError',
                isA<StateError>(),
              )
              .having(
                (NoteAssertionFailure error) => error.message,
                'message',
                allOf(
                  contains('Expected summary "wrong"'),
                  contains('Release — Ship the template.'),
                ),
              ),
        ),
      );
    });

    test('propagates the summariser ArgumentError for a bad length', () {
      // Assert
      expect(
        () => assertNoteSummary(note, 'anything', maxLength: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
