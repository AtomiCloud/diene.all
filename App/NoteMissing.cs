using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.App;

/// <summary>A demo consumer-owned problem registered beside the portable baseline.</summary>
[Description("The requested note does not exist.")]
public sealed class NoteMissing : IDomainProblem
{
    /// <summary>Creates an empty catalog instance.</summary>
    public NoteMissing()
    {
    }

    /// <summary>Creates a problem for a missing note.</summary>
    public NoteMissing(string noteId)
    {
        NoteId = noteId ?? throw new ArgumentNullException(nameof(noteId));
        Detail = $"Note '{noteId}' does not exist.";
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "note_missing";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Note Missing";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the requested note identifier.</summary>
    [Description("The identifier of the note that was requested.")]
    public string NoteId { get; } = string.Empty;
}

internal sealed class UnregisteredDemoProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "unregistered_demo";

    [JsonIgnore]
    public string Title => "Unregistered Demo";

    [JsonIgnore]
    public string Detail => "This problem intentionally exercises the uncatalogued-to-500 rule.";

    [JsonIgnore]
    public string Version => "v1";

    public string Marker => "catalog-loop";
}
