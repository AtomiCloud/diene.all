import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';

/// The IdP-specific implementation behind a provider interface.
///
/// Logto is the ONLY provider implementation in v1 (no second-IdP work is
/// planned); the interface exists so consumers and tests fake the IdP without
/// pulling the Logto SDK. Every method may throw — the [SessionController] and
/// the IAuth seam wrap thrown errors into problem-typed [Result]s.
abstract interface class AuthProvider {
  /// Runs the interactive sign-in. [extraParams] carries the deferred-login
  /// one-time token / login hint for the app-handoff flow.
  Future<SessionTokens> signIn({Map<String, String> extraParams});

  /// Exchanges a rotating refresh token for a fresh pair.
  Future<SessionTokens> refresh(SessionTokens current);

  /// Silently re-mints the access token on app open, keeping the refresh token.
  Future<SessionTokens> reMintOnOpen(SessionTokens current);

  /// Clears the provider-side session.
  Future<void> signOut();

  /// Acquires a fresh access token for one resource (Logto per-resource token).
  Future<ResourceToken> resourceToken(ResourceKey key);

  /// The raw OIDC ID token for the active session, if any. Needed by the
  /// onboarding `POST /User` create body.
  Future<String?> idToken();

  /// Forces acquisition of a FRESH claim-bearing JWT — bypassing any cached
  /// token — after a server-side claim write such as OnboardSync (C0 §13), and
  /// returns the EXACT raw token whose payload the home-claim parser decodes.
  ///
  /// This is distinct from [idToken] (which returns the possibly-stale stored
  /// token) and from [reMintOnOpen] (which may be served from cache): a stale
  /// token here would let a just-written `home_landscape` claim go unseen.
  /// Implementations MUST guarantee the returned token reflects current server
  /// state, or return `null` to FAIL CLOSED when that cannot be established.
  Future<String?> freshClaimToken();
}
