import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('landscape', () {
    test('returns the injected build-time identity', () {
      // Arrange.
      const FakeLandscapeSource source = FakeLandscapeSource('lapras');

      // Act.
      final String value = landscape(source: source);

      // Assert.
      expect(value, 'lapras');
    });

    test('rejects a missing identity instead of detecting one', () {
      // Arrange.
      const DartDefineLandscapeSource source = DartDefineLandscapeSource();

      // Act and assert.
      expect(() => landscape(source: source), throwsStateError);
    });
  });
}
