using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// A typed problem the demo deliberately leaves OUT of the catalog.
/// </summary>
/// <remarks>
/// It exists to show what an unregistered problem does at the boundary: the published catalog
/// logs it and answers 500, and the envelope's type becomes <c>about:blank</c> rather than a
/// documentation URI that would 404. Demonstrating that is worth a type, because the failure it
/// models — forgetting to register a problem — is silent until a caller hits it in production.
/// </remarks>
[Description("A demo problem intentionally absent from the catalog.")]
public sealed class DemoUnregisteredProblem : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public DemoUnregisteredProblem()
    {
    }

    /// <summary>Creates a populated instance naming the note that triggered it.</summary>
    public DemoUnregisteredProblem(string noteId)
    {
        this.Detail = $"Note '{noteId}' triggered an unregistered problem.";
        this.NoteId = noteId;
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "demo_unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Demo Unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the note that triggered the problem.</summary>
    [Description("The note that triggered the problem.")]
    public string NoteId { get; } = string.Empty;
}
