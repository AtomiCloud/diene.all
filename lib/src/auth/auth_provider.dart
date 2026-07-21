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
}
