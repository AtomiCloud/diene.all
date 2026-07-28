using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// A typed problem the demo deliberately leaves OUT of the catalog.
/// </summary>
/// <remarks>
/// It exists to show what an unregistered problem does at the boundary: the published catalog logs
/// it and answers 500, and the envelope's type becomes <c>about:blank</c> rather than a
/// documentation URI that would 404. Demonstrating that is worth a type, because the failure it
/// models — forgetting to register a problem — is silent until a caller hits it in production.
/// It carries no parameterless constructor: that overload exists so a catalog can register a type
/// and export its schema, and this problem is never registered.
/// </remarks>
/// <param name="noteId">The note that triggered the problem.</param>
[Description("A demo problem intentionally absent from the catalog.")]
public sealed class DemoUnregisteredProblem(string noteId) : IDomainProblem
{
    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "demo_unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Demo Unregistered";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = $"Note '{noteId}' triggered an unregistered problem.";

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";
}
