/// The `/User` onboarding surface a backend exposes (C0 §8).
///
/// Implementations issue exactly the HTTP calls the machine asks for and return
/// the raw status code; a transport failure throws (the machine maps it to
/// `error`). Callers pass the designated onboarding-resource access token.
abstract interface class UserDirectory {
  /// `GET {backend}/User/Me` with the bearer [accessToken]. Returns the status
  /// (200 = row exists, 404 = create path).
  Future<int> getUserMe({
    required String backendId,
    required String accessToken,
  });

  /// `POST {backend}/User` with the bearer [accessToken] and body
  /// `{ "idToken": ..., "accessToken": ... }`. Any 2xx or 409 is create-or-ok.
  Future<int> postUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  });
}
