using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>A request failed field or value validation.</summary>
[Description("The request contains one or more validation errors.")]
public sealed class ValidationError : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public ValidationError()
    {
    }

    /// <summary>Creates a populated validation problem.</summary>
    public ValidationError(string detail, IDictionary<string, string[]> errors)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        Errors = errors is null
            ? throw new ArgumentNullException(nameof(errors))
            : new Dictionary<string, string[]>(errors, StringComparer.Ordinal);
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "validation_error";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Validation Error";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets validation messages grouped by field.</summary>
    [Description("Validation messages grouped by the field that failed validation.")]
    public IReadOnlyDictionary<string, string[]> Errors { get; } = new Dictionary<string, string[]>();
}
