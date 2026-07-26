using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>A caller has not authenticated.</summary>
[Description("The caller is not authenticated to access the resource.")]
public sealed class Unauthenticated : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public Unauthenticated()
    {
    }

    /// <summary>Creates a populated authentication problem.</summary>
    public Unauthenticated(string detail) =>
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "unauthenticated";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Unauthenticated";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";
}
