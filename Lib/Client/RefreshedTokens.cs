namespace AtomiCloud.Diene.AuthEngine.Client;

/// <summary>
/// The outcome of a refresh: a fresh access token, and — when rotation is on — the
/// replacement refresh token that must be stored in place of the one just presented.
/// </summary>
/// <param name="Access">The newly minted access token.</param>
/// <param name="RefreshToken">
/// The refresh token to persist. With rotation enabled this differs from the presented
/// token; the caller must overwrite rather than keep both, since the old one is retired
/// and re-presenting it is what triggers reuse detection.
/// </param>
public sealed record RefreshedTokens(TokenResponse Access, string RefreshToken);
