import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Journey', () {
    test('runs every step when all pass', () async {
      // Arrange.
      final List<String> ran = <String>[];
      final Journey journey = Journey('all-pass', <JourneyStep>[
        JourneyStep('one', () async {
          ran.add('one');
          return true;
        }),
        JourneyStep('two', () async {
          ran.add('two');
          return true;
        }),
      ]);
      // Act.
      final JourneyResult result = await journey.run();
      // Assert.
      expect(result.ok, isTrue);
      expect(result.firstFailure, isNull);
      expect(ran, <String>['one', 'two']);
    });

    test('stops at the first failing step', () async {
      final List<String> ran = <String>[];
      final Journey journey = Journey('fail-fast', <JourneyStep>[
        JourneyStep('one', () async {
          ran.add('one');
          return true;
        }),
        JourneyStep('two', () async {
          ran.add('two');
          return false;
        }),
        JourneyStep('three', () async {
          ran.add('three');
          return true;
        }),
      ]);
      final JourneyResult result = await journey.run();
      expect(result.ok, isFalse);
      expect(result.firstFailure?.name, 'two');
      expect(ran, <String>['one', 'two']); // 'three' never ran.
    });

    test('a thrown step is recorded as a failure with detail', () async {
      final Journey journey = Journey('throwing', <JourneyStep>[
        JourneyStep('boom', () async => throw StateError('nope')),
      ]);
      final JourneyResult result = await journey.run();
      expect(result.ok, isFalse);
      expect(result.firstFailure?.name, 'boom');
      expect(result.firstFailure?.detail, contains('nope'));
    });
  });
}
