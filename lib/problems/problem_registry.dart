/// Problem registry port (argon feature port 3 of 5).
///
/// Maps a [Problem] onto the *presentation contract* the UI needs: which tier to
/// render, what to say, and whether a retry affordance is offered. The mapping is
/// data (a registry of [ProblemErrorInfo] keyed by problem type URN), not a chain
/// of `if (problem.type == ...)` at each call site.
///
/// Separation of concerns against the two neighbouring ports:
/// * the runtime endpoint classifier in `lib/problems/catalog_classification.dart` maps *endpoint + HTTP status* → `Problem`
///   (transport → domain).
/// * this file maps *`Problem`* → `ProblemErrorInfo` (domain → presentation).
/// * `lib/problems/catalog_classification.dart` composes the two.
///
/// Lookup is total: an unregistered type falls back to a tier derived from the
/// problem itself, and the fallback is *flagged* ([ProblemErrorInfo.registered]
/// is false) so an uncatalogued problem is visibly distinct from a registered
/// one rather than silently indistinguishable.
library;

import 'package:diene_problems/diene_problems.dart' hide ProblemRegistry;

/// How prominently a problem is surfaced.
enum ProblemTier {
  /// Inline / banner: the user can carry on, usually by retrying.
  recoverable,

  /// Blocking: the screen cannot proceed.
  fatal,
}

/// The presentation contract for one problem type.
final class ProblemErrorInfo {
  const ProblemErrorInfo({
    required this.tier,
    required this.headline,
    required this.guidance,
    required this.retryable,
    this.registered = true,
  });

  /// Which tier the UI renders.
  final ProblemTier tier;

  /// Short user-facing headline.
  final String headline;

  /// One-line "what to do next".
  final String guidance;

  /// Whether the UI offers a retry affordance.
  final bool retryable;

  /// False when this info came from the fallback path (type not registered).
  ///
  /// Kept so callers can feed uncatalogued problems back into the catalog loop
  /// instead of quietly rendering them as if they were known.
  final bool registered;

  /// Whether this problem blocks the screen.
  bool get isFatal => tier == ProblemTier.fatal;

  ProblemErrorInfo asUnregistered() => ProblemErrorInfo(
    tier: tier,
    headline: headline,
    guidance: guidance,
    retryable: retryable,
    registered: false,
  );
}

/// Notified once per lookup that missed the registry.
typedef UnregisteredProblemSink = void Function(Problem problem);

/// A registry of problem-type URN → [ProblemErrorInfo].
///
/// Stateless apart from the immutable registry map; the miss sink is injected.
final class ProblemRegistry {
  ProblemRegistry({
    required Map<String, ProblemErrorInfo> entries,
    UnregisteredProblemSink? onUnregistered,
  }) : _entries = Map<String, ProblemErrorInfo>.unmodifiable(entries),
       _onUnregistered = onUnregistered ?? _ignore;

  final Map<String, ProblemErrorInfo> _entries;
  final UnregisteredProblemSink _onUnregistered;

  /// The registered type URNs, for diagnostics and tests.
  Iterable<String> get registeredTypes => _entries.keys;

  /// Whether [type] has an explicit registration.
  bool isRegistered(String type) => _entries.containsKey(type);

  /// Resolve the presentation contract for [problem].
  ///
  /// A registered type returns its entry verbatim. An unregistered type returns
  /// [fallbackFor] and notifies the miss sink exactly once.
  ProblemErrorInfo resolve(Problem problem) {
    final ProblemErrorInfo? entry = _entries[problem.type];
    if (entry != null) {
      return entry;
    }
    _onUnregistered(problem);
    return fallbackFor(problem);
  }

  /// The fallback contract for an unregistered problem type.
  ///
  /// The tier is derived from the problem's own `recoverable` flag and status:
  /// only an explicitly recoverable, non-5xx problem degrades gracefully.
  /// Everything else — including anything 5xx — is fatal, which is what makes
  /// "uncatalogued behaves as 5xx" hold in the classifier above this.
  static ProblemErrorInfo fallbackFor(Problem problem) {
    final bool recoverable = problem.recoverable && problem.status < 500;
    return ProblemErrorInfo(
      tier: recoverable ? ProblemTier.recoverable : ProblemTier.fatal,
      headline: problem.title,
      guidance: recoverable
          ? 'Something went wrong. Try again.'
          : 'Something went wrong on our side. Please try again later.',
      retryable: recoverable,
      registered: false,
    );
  }

  /// A registry with [additions] merged over this one's entries.
  ///
  /// Used to layer per-feature registrations over an app-wide base without
  /// mutating either.
  ProblemRegistry extendedWith(
    Map<String, ProblemErrorInfo> additions, {
    UnregisteredProblemSink? onUnregistered,
  }) => ProblemRegistry(
    entries: <String, ProblemErrorInfo>{..._entries, ...additions},
    onUnregistered: onUnregistered ?? _onUnregistered,
  );

  static void _ignore(Problem problem) {}
}
