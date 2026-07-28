/// Content state machine port (argon feature port 2 of 5).
///
/// A total, immutable Loading / Empty / Error / Content state machine. Every
/// screen that loads remote data drives its UI from this one machine so the four
/// tiers are never re-invented per screen (and never silently collapsed to
/// "spinner or data").
///
/// Design notes:
/// * [ContentState] is a sealed class, so `switch` over it is exhaustive — a new
///   tier cannot be added without every consumer being forced to handle it.
/// * Transitions are pure functions on [ContentMachine], not mutations: each
///   returns the next state. The machine itself holds no state, so it is safe to
///   share and trivial to test.
/// * Emptiness is decided by an injected predicate, so "empty" means what the
///   domain says it means (an empty list, a zero balance) rather than `null`.
/// * The Loading tier carries the previous content, so a refresh can keep
///   showing stale data instead of flashing a spinner over the whole screen.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// The four content tiers.
sealed class ContentState<T> {
  const ContentState();

  /// Fold over every tier. Total by construction.
  R fold<R>({
    required R Function(T? previous) onLoading,
    required R Function() onEmpty,
    required R Function(Problem problem, T? previous) onError,
    required R Function(T value) onContent,
  }) => switch (this) {
    ContentLoading<T>(:final T? previous) => onLoading(previous),
    ContentEmpty<T>() => onEmpty(),
    ContentError<T>(:final Problem problem, :final T? previous) => onError(
      problem,
      previous,
    ),
    ContentValue<T>(:final T value) => onContent(value),
  };

  /// Whether a load is in flight.
  bool get isLoading => this is ContentLoading<T>;

  /// The content currently displayable, if any.
  ///
  /// Non-null for [ContentValue], and for [ContentLoading] / [ContentError] that
  /// carry stale content from a previous successful load.
  T? get displayable => switch (this) {
    ContentValue<T>(:final T value) => value,
    ContentLoading<T>(:final T? previous) => previous,
    ContentError<T>(:final T? previous) => previous,
    ContentEmpty<T>() => null,
  };
}

/// A load is in flight. [previous] is the last successful content, if any.
final class ContentLoading<T> extends ContentState<T> {
  const ContentLoading({this.previous});

  final T? previous;

  @override
  bool operator ==(Object other) =>
      other is ContentLoading<T> && other.previous == previous;

  @override
  int get hashCode => Object.hash(ContentLoading<T>, previous);

  @override
  String toString() => 'ContentLoading(previous: $previous)';
}

/// The load succeeded but the payload is empty per the domain's own predicate.
final class ContentEmpty<T> extends ContentState<T> {
  const ContentEmpty();

  @override
  bool operator ==(Object other) => other is ContentEmpty<T>;

  @override
  int get hashCode => Object.hash(ContentEmpty<T>, 0);

  @override
  String toString() => 'ContentEmpty()';
}

/// The load failed. [previous] is the last successful content, if any.
final class ContentError<T> extends ContentState<T> {
  const ContentError(this.problem, {this.previous});

  final Problem problem;
  final T? previous;

  @override
  bool operator ==(Object other) =>
      other is ContentError<T> &&
      other.problem.type == problem.type &&
      other.problem.status == problem.status &&
      other.previous == previous;

  @override
  int get hashCode => Object.hash(problem.type, problem.status, previous);

  @override
  String toString() => 'ContentError(${problem.type}, previous: $previous)';
}

/// The load succeeded with non-empty content.
final class ContentValue<T> extends ContentState<T> {
  const ContentValue(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is ContentValue<T> && other.value == value;

  @override
  int get hashCode => Object.hash(ContentValue<T>, value);

  @override
  String toString() => 'ContentValue($value)';
}

/// Decides whether a successfully loaded [value] should render as
/// [ContentEmpty].
typedef EmptinessPredicate<T> = bool Function(T value);

/// The transitions between the four tiers.
///
/// Stateless: every method takes the current state and returns the next one, so
/// a controller owns the state while the machine owns the *rules*.
final class ContentMachine<T> {
  const ContentMachine({required this.isEmpty});

  /// Machine for an [Iterable] payload, where empty means "no elements".
  static ContentMachine<C> forCollection<C extends Iterable<Object?>>() =>
      ContentMachine<C>(isEmpty: (C value) => value.isEmpty);

  /// Machine for a payload that is never empty (a single record, a total).
  static ContentMachine<C> neverEmpty<C>() =>
      ContentMachine<C>(isEmpty: (C value) => false);

  final EmptinessPredicate<T> isEmpty;

  /// The state a screen starts in, before any load has been attempted.
  ContentState<T> initial() => ContentLoading<T>();

  /// Begin (or re-begin) a load.
  ///
  /// Content already on screen is carried into the loading tier so a refresh
  /// does not blank the screen. Coming from [ContentEmpty] carries nothing:
  /// "empty" is a completed answer, not stale content.
  ContentState<T> startLoading(ContentState<T> current) =>
      ContentLoading<T>(previous: current.displayable);

  /// Apply a load [result].
  ///
  /// Ok routes to [ContentEmpty] or [ContentValue] via [isEmpty]; failure
  /// routes to [ContentError], retaining any stale content for a
  /// keep-showing-data-with-a-banner presentation.
  ContentState<T> resolve(ContentState<T> current, Result<T> result) =>
      result.match<ContentState<T>>(
        ok: (T value) =>
            isEmpty(value) ? ContentEmpty<T>() : ContentValue<T>(value),
        err: (Problem problem) =>
            ContentError<T>(problem, previous: current.displayable),
      );

  /// Retry after an error: equivalent to [startLoading], but refuses to retry
  /// from a non-error tier so a stray retry tap cannot cancel a live load.
  ContentState<T> retry(ContentState<T> current) => switch (current) {
    ContentError<T>(:final T? previous) => ContentLoading<T>(
      previous: previous,
    ),
    _ => current,
  };
}
