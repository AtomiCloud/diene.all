using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>A supplied value could not be parsed as JSON.</summary>
[Description("The supplied value could not be parsed as JSON.")]
public sealed class InvalidJson : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public InvalidJson()
    {
    }

    /// <summary>Creates a populated invalid-JSON problem.</summary>
    public InvalidJson(string detail, string invalidString)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        InvalidString = invalidString ?? throw new ArgumentNullException(nameof(invalidString));
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "invalid_json";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Invalid JSON";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the value that failed JSON parsing.</summary>
    [Description("The original value that failed JSON parsing.")]
    public string InvalidString { get; } = string.Empty;
}
