using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>An authenticated caller lacks a required permission.</summary>
[Description("The authenticated caller is not authorized to access the resource.")]
public sealed class Unauthorized : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public Unauthorized()
    {
    }

    /// <summary>Creates a populated authorization problem.</summary>
    public Unauthorized(string detail, IEnumerable<string> granted, IEnumerable<string> required)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        Granted = [.. granted ?? throw new ArgumentNullException(nameof(granted))];
        Required = [.. required ?? throw new ArgumentNullException(nameof(required))];
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "unauthorized";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Unauthorized";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets permissions granted to the caller.</summary>
    [Description("Permissions granted to the caller.")]
    public IReadOnlyList<string> Granted { get; } = [];

    /// <summary>Gets permissions required by the resource.</summary>
    [Description("Permissions required to access the resource.")]
    public IReadOnlyList<string> Required { get; } = [];
}
