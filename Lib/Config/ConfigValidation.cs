using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>Shared configuration validators, kept total and Result-returning.</summary>
internal static class ConfigValidation
{
    /// <summary>
    /// Accepts only a canonical origin: an absolute http or https URI with no credentials,
    /// path, query, or fragment. A trailing "/" is the empty path and is permitted because
    /// <see cref="Uri" /> always materialises one.
    /// </summary>
    internal static Result<Uri, ConfigError> CanonicalOrigin(string field, string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return new ConfigError(field, "Endpoint must not be blank.");

        if (!Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri))
        {
            return new ConfigError(field, "Endpoint must be an absolute URI.");
        }

        if (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)
        {
            return new ConfigError(field, "Endpoint must use http or https.");
        }

        if (!string.IsNullOrEmpty(uri.UserInfo))
        {
            return new ConfigError(field, "Endpoint must not carry credentials.");
        }

        if (uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
        {
            return new ConfigError(field, "Endpoint must be a canonical origin without path, query, or fragment.");
        }

        return uri;
    }
}
