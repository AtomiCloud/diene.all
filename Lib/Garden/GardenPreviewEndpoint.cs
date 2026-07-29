using System.Text.RegularExpressions;

namespace AtomiCloud.Diene.E2e.Garden;

/// <summary>Resolves a Garden preview URL only when its namespace fixture matches.</summary>
public static class GardenPreviewEndpoint
{
    private static readonly Regex DnsLabel = new(
        "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$",
        RegexOptions.CultureInvariant);

    /// <summary>Resolves one validated Garden preview endpoint.</summary>
    public static Uri Resolve(
        string hostname,
        GardenNamespaceFixture fixture,
        string scheme = "https",
        int? port = null,
        string path = "/")
    {
        ArgumentNullException.ThrowIfNull(fixture);

        var expected = ValidateDnsName(fixture.Hostname, "fixture");
        var actual = ValidateDnsName(hostname, nameof(hostname));
        if (!string.Equals(actual, expected, StringComparison.Ordinal))
        {
            throw new E2eHarnessException(
                $"Garden hostname does not match namespace fixture: expected {expected}");
        }

        if (scheme is not ("http" or "https"))
        {
            throw new E2eHarnessException("scheme must be http or https");
        }

        if (port is < 1 or > 65535)
        {
            throw new E2eHarnessException("port must be an integer from 1 through 65535");
        }

        if (!path.StartsWith("/", StringComparison.Ordinal) ||
            path.StartsWith("//", StringComparison.Ordinal))
        {
            throw new E2eHarnessException("path must be an absolute URL path");
        }

        return new UriBuilder(scheme, actual, port ?? -1, path).Uri;
    }

    private static string ValidateDnsName(string value, string field)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Length > 253 ||
            value.Split('.').Any(label => !DnsLabel.IsMatch(label)))
        {
            throw new E2eHarnessException($"{field} must be a lowercase DNS name");
        }

        return value;
    }
}
