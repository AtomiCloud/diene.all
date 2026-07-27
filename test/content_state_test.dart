import 'package:diene_flutter_base/content/content_state.dart';
import 'package:diene_flutter_base/core/result.dart';
import 'package:flutter_test/flutter_test.dart';

const Problem _offline = Problem(
  type: 'urn:test:offline',
  title: 'Offline',
  status: 503,
  recoverable: true,
);

/// Names the tier a state lands in, so a flipped transition shows up as a
/// changed VALUE ('empty' vs 'content') rather than a type-check nuance.
String _tier<T>(ContentState<T> state) => state.fold<String>(
  onLoading: (T? _) => 'loading',
  onEmpty: () => 'empty',
  onError: (Problem problem, T? stale) => 'error',
  onContent: (T _) => 'content',
);

void main() {
  final ContentMachine<List<String>> machine =
      ContentMachine.forCollection<List<String>>();

  group('content state machine transitions', () {
    test('a screen starts loading with nothing stale', () {
      final ContentState<List<String>> initial = machine.initial();

      expect(_tier(initial), 'loading');
      expect(initial.isLoading, isTrue);
      expect(initial.displayable, isNull);
    });

    test('loading -> content on a non-empty success', () {
      final ContentState<List<String>> next = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>['a', 'b']),
      );

      expect(_tier(next), 'content');
      expect(next.displayable, <String>['a', 'b']);
      expect(next.isLoading, isFalse);
    });

    test('loading -> empty on an empty success (not content)', () {
      final ContentState<List<String>> next = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>[]),
      );

      expect(_tier(next), 'empty');
      expect(next.displayable, isNull);
    });

    test('loading -> error on a failure, carrying the problem', () {
      final ContentState<List<String>> next = machine.resolve(
        machine.initial(),
        const Failure<List<String>>(_offline),
      );

      expect(_tier(next), 'error');
      final Problem seen = next.fold<Problem>(
        onLoading: (List<String>? _) => fail('expected error'),
        onEmpty: () => fail('expected error'),
        onError: (Problem problem, List<String>? stale) => problem,
        onContent: (List<String> _) => fail('expected error'),
      );
      expect(seen.type, 'urn:test:offline');
      expect(seen.status, 503);
    });

    test('content -> loading keeps the stale content on screen', () {
      final ContentState<List<String>> content = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>['a']),
      );
      final ContentState<List<String>> refreshing = machine.startLoading(
        content,
      );

      expect(_tier(refreshing), 'loading');
      expect(refreshing.displayable, <String>['a'], reason: 'no spinner flash');
    });

    test('content -> error keeps the stale content for a banner', () {
      final ContentState<List<String>> content = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>['a']),
      );
      final ContentState<List<String>> failed = machine.resolve(
        machine.startLoading(content),
        const Failure<List<String>>(_offline),
      );

      expect(_tier(failed), 'error');
      expect(failed.displayable, <String>['a']);
    });

    test('empty -> loading carries nothing (empty is an answer)', () {
      final ContentState<List<String>> empty = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>[]),
      );

      expect(machine.startLoading(empty).displayable, isNull);
    });

    test('empty -> content once the payload arrives', () {
      final ContentState<List<String>> empty = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>[]),
      );
      final ContentState<List<String>> filled = machine.resolve(
        machine.startLoading(empty),
        const Success<List<String>>(<String>['a']),
      );

      expect(_tier(filled), 'content');
    });

    test('content -> empty when the payload drains', () {
      final ContentState<List<String>> content = machine.resolve(
        machine.initial(),
        const Success<List<String>>(<String>['a']),
      );
      final ContentState<List<String>> drained = machine.resolve(
        machine.startLoading(content),
        const Success<List<String>>(<String>[]),
      );

      expect(_tier(drained), 'empty');
      expect(drained.displayable, isNull);
    });

    test('error -> loading -> content recovers via retry', () {
      final ContentState<List<String>> failed = machine.resolve(
        machine.initial(),
        const Failure<List<String>>(_offline),
      );
      final ContentState<List<String>> retrying = machine.retry(failed);
      final ContentState<List<String>> recovered = machine.resolve(
        retrying,
        const Success<List<String>>(<String>['a']),
      );

      expect(_tier(retrying), 'loading');
      expect(_tier(recovered), 'content');
    });

    test('retry from a non-error tier is a no-op', () {
      final ContentState<List<String>> loading = machine.initial();
      final ContentState<List<String>> content = machine.resolve(
        loading,
        const Success<List<String>>(<String>['a']),
      );

      expect(machine.retry(loading), same(loading));
      expect(machine.retry(content), same(content));
      expect(_tier(machine.retry(content)), 'content');
    });

    test('emptiness is the domain predicate, not null-ness', () {
      final ContentMachine<int> balance = ContentMachine<int>(
        isEmpty: (int value) => value == 0,
      );
      final ContentMachine<int> anyNumber = ContentMachine.neverEmpty<int>();

      expect(_tier(balance.resolve(balance.initial(), const Success<int>(0))),
          'empty');
      expect(_tier(balance.resolve(balance.initial(), const Success<int>(5))),
          'content');
      expect(_tier(anyNumber.resolve(anyNumber.initial(), const Success<int>(0))),
          'content');
    });

    test('states of the same tier and payload compare equal', () {
      expect(
        const ContentValue<List<String>>(<String>['a']),
        const ContentValue<List<String>>(<String>['a']),
      );
      expect(const ContentEmpty<int>(), const ContentEmpty<int>());
      expect(
        const ContentValue<int>(1) == const ContentValue<int>(2),
        isFalse,
      );
    });
  });
}
