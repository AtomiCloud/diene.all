import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  group('landscape', () {
    test('returns the injected store track', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('lapras');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isOk, reason: describe(track));
      expect(track.unwrap(), 'lapras');
    });

    test('trims surrounding whitespace', () {
      // A define passed through a shell script commonly arrives padded.
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('  pichu \n');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isOk, reason: describe(track));
      expect(track.unwrap(), 'pichu');
    });

    test('reports an absent define as landscape_missing', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isErr, reason: describe(track));
      final Problem problem = track.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.landscapeMissing.wireId);
      expect(problem.status, 400);
      expect(problem.data['define'], landscapeDefineKey);
      expect(problem.title, contains(landscapeDefineKey));
    });

    test(
      'treats a whitespace-only define as absent, not as the empty track',
      () {
        // C0 §3 blank-is-unset governs every other define this package reads;
        // the landscape must not be the one place a blank means something.
        // Arrange
        const LandscapeSource source = FakeLandscapeSource('   ');

        // Act
        final Result<String> track = landscape(source: source);

        // Assert
        expect(track, isErr, reason: describe(track));
        expect(
          track.unwrapErr().data['code'],
          ConfigProblemCode.landscapeMissing.wireId,
        );
      },
    );
  });

  group('DartDefineLandscapeSource', () {
    test('reads an explicitly supplied value', () {
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource(value: 'raichu');

      // Act & Assert
      expect(source.read(), 'raichu');
    });

    test('defaults to the compile-time define, absent in a plain test run', () {
      // No --dart-define is passed to `dart test`, so the constant is '' and
      // the accessor reports the missing-identity problem. This is the real
      // default path, not a fake.
      // Arrange
      const LandscapeSource source = DartDefineLandscapeSource();

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(source.read(), '');
      expect(track, isErr, reason: describe(track));
    });

    test('is the default source of landscape()', () {
      // Act
      final Result<String> track = landscape();

      // Assert
      expect(track, isErr, reason: describe(track));
      expect(
        track.unwrapErr().data['code'],
        ConfigProblemCode.landscapeMissing.wireId,
      );
    });

    test('never inspects host or runtime state', () {
      // The accessor contract: two sources with the same value agree, and the
      // answer depends on nothing else. A detector could not satisfy this.
      // Arrange
      const LandscapeSource injected = FakeLandscapeSource('lapras');
      const LandscapeSource define = DartDefineLandscapeSource(value: 'lapras');

      // Assert
      expect(landscape(source: injected).unwrap(), 'lapras');
      expect(landscape(source: define).unwrap(), 'lapras');
    });
  });

  group('landscapeDefineKey', () {
    test('is the documented DIENE_LANDSCAPE define', () {
      expect(landscapeDefineKey, 'DIENE_LANDSCAPE');
    });
  });
}
