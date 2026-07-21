import '../auth/claims.dart';
import '../contracts/problem.dart';
import '../contracts/result.dart';
import 'landscape_selector.dart';

/// Reads the AUTHORITATIVE `home_landscape` claim from the provider's
/// existing/issued JWT (C0 §13). Returns `null` when no token exists yet or the
/// token carries no claim. This — not local storage — decides the home.
typedef HomeClaimReader = Future<String?> Function();

/// Builds a [HomeClaimReader] that decodes `home_landscape` from the provider's
/// current ID token. Pass `AuthProvider.idToken` (or the access-token reader).
/// A missing token or absent claim yields `null` (→ Doc B sign-up path).
HomeClaimReader jwtHomeClaimReader(Future<String?> Function() readToken) =>
    () async {
      final String? token = await readToken();
      if (token == null || token.isEmpty) {
        return null;
      }
      return Claims.home(Claims.decode(token));
    };

/// Persists the client's known home landscape as a NON-AUTHORITATIVE mirror of
/// the `home_landscape` JWT claim (C0 §13). It never chooses the home; it only
/// caches a value the JWT already made authoritative, for offline UI hints.
abstract interface class HomeClaimStore {
  Future<String?> read();
  Future<void> write(String landscape);
  Future<void> clear();
}

/// How the home landscape was resolved on this sign-in.
enum HomeResolutionKind {
  /// The authoritative JWT `home_landscape` claim was present — routed straight
  /// home, no Doc B, no picker.
  fromClaim,

  /// The authoritative claim was absent — the Doc B selector ran (sign-up).
  selected,
}

/// The resolved home landscape plus how it was obtained.
final class HomeResolution {
  const HomeResolution({required this.landscape, required this.kind});

  final String landscape;
  final HomeResolutionKind kind;
}

/// Resolves the home landscape on EVERY sign-in (C0 §13).
///
/// The `home_landscape` claim rides the ID/access JWT and is AUTHORITATIVE:
/// the resolver decodes it through [HomeClaimReader]. When present it decides
/// the home (and is mirrored into the local store); when absent the Doc B
/// selector runs (sign-up only). The local store is only a mirror — a stale or
/// tampered cache can NEVER choose the home, and a changed/removed Logto
/// `custom_data.home_landscape` is always observed on the next sign-in.
final class HomeClaimResolver {
  const HomeClaimResolver({
    required HomeClaimReader claimReader,
    required LandscapeSelectorClient selector,
    HomeClaimStore? store,
  }) : _claimReader = claimReader,
       _selector = selector,
       _store = store;

  final HomeClaimReader _claimReader;
  final LandscapeSelectorClient _selector;
  final HomeClaimStore? _store;

  /// Reads the AUTHORITATIVE `home_landscape` claim from the provider's JWT,
  /// WITHOUT running Doc B. `null` (inside a [Success]) means the claim is
  /// absent. Used by the coordinator to re-check the freshly issued token after
  /// login so a server-changed/removed claim is always observed.
  Future<Result<String?>> authoritativeHome() async {
    try {
      final String? claim = await _claimReader();
      return Success<String?>(claim != null && claim.isNotEmpty ? claim : null);
    } on Object catch (error) {
      return Failure<String?>(
        Problem(
          type: 'urn:diene:problem:home-claim-read',
          title: 'Could not read the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }

  /// Resolves the home landscape. Consults the authoritative JWT claim first;
  /// runs the Doc B selector ONLY when that claim is absent (sign-up).
  Future<Result<HomeResolution>> resolve({String? preferred}) async {
    final Result<String?> read = await authoritativeHome();
    if (read is Failure<String?>) {
      return Failure<HomeResolution>(read.problem);
    }
    final String? authoritative = (read as Success<String?>).value;
    if (authoritative != null && authoritative.isNotEmpty) {
      // Mirror the authoritative value; the store is not consulted to decide.
      await _mirror(authoritative);
      return Success<HomeResolution>(
        HomeResolution(
          landscape: authoritative,
          kind: HomeResolutionKind.fromClaim,
        ),
      );
    }
    // Authoritative claim absent → sign-up path: Doc B → ping → pick.
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
  Future<void> commit(String landscape) => _mirror(landscape);

  /// Clears the cached home (e.g. on full sign-out / re-home event).
  Future<void> forget() async => _store?.clear();

  Future<void> _mirror(String landscape) async {
    final HomeClaimStore? store = _store;
    if (store == null) {
      return;
    }
    // Best-effort mirror; a store failure must never override the JWT decision.
    try {
      await store.write(landscape);
    } on Object {
      // Non-authoritative cache; ignore write failures.
    }
  }
}
