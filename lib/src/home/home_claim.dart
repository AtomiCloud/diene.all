import '../contracts/problem.dart';
import '../contracts/result.dart';
import 'landscape_selector.dart';

/// Persists the client's known home landscape (mirrors the `home_landscape`
/// JWT claim OnboardSync writes server-side, C0 §13).
abstract interface class HomeClaimStore {
  Future<String?> read();
  Future<void> write(String landscape);
  Future<void> clear();
}

/// How the home landscape was resolved on this sign-in.
enum HomeResolutionKind {
  /// The claim was present — routed straight home, no Doc B, no picker.
  cached,

  /// The claim was absent — Doc B selector ran (sign-up path).
  selected,
}

/// The resolved home landscape plus how it was obtained.
final class HomeResolution {
  const HomeResolution({required this.landscape, required this.kind});

  final String landscape;
  final HomeResolutionKind kind;
}

/// Resolves the home landscape on EVERY sign-in (C0 §13):
/// present → route directly (no Doc B); absent → Doc B selector (sign-up only).
///
/// The authoritative claim rides the JWT and is written server-side by
/// OnboardSync; [commit] mirrors the accepted value into the local store so the
/// next sign-in takes the cached fast path.
final class HomeClaimResolver {
  const HomeClaimResolver({
    required HomeClaimStore store,
    required LandscapeSelectorClient selector,
  }) : _store = store,
       _selector = selector;

  final HomeClaimStore _store;
  final LandscapeSelectorClient _selector;

  /// Resolves the home landscape. Runs the Doc B selector ONLY when the claim
  /// is absent (sign-up).
  Future<Result<HomeResolution>> resolve({String? preferred}) async {
    final String? cached;
    try {
      cached = await _store.read();
    } on Object catch (error) {
      return Failure<HomeResolution>(
        Problem(
          type: 'urn:diene:problem:home-claim-read',
          title: 'Could not read the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
    if (cached != null && cached.isNotEmpty) {
      return Success<HomeResolution>(
        HomeResolution(landscape: cached, kind: HomeResolutionKind.cached),
      );
    }
    // Absent → sign-up path: Doc B → ping → pick.
    final Result<String> selected = await _selector.selectHome(
      preferred: preferred,
    );
    return selected.map(
      (String landscape) => HomeResolution(
        landscape: landscape,
        kind: HomeResolutionKind.selected,
      ),
    );
  }

  /// Mirrors the OnboardSync-written home claim into the local store.
  Future<void> commit(String landscape) => _store.write(landscape);

  /// Clears the cached home (e.g. on full sign-out / re-home event).
  Future<void> forget() => _store.clear();
}
