using System.Text.Json.Nodes;

namespace AtomiCloud.Diene.Problems;

/// <summary>Exports registered problem payload schemas for the Problem CR channel.</summary>
public interface IProblemExporter
{
    /// <summary>Exports one registered descriptor.</summary>
    ProblemExport Export(ProblemDescriptor descriptor);

    /// <summary>Exports every registered descriptor.</summary>
    IReadOnlyList<ProblemExport> ExportAll();
}

/// <summary>The C0 catalog entry shape produced from a registered typed problem.</summary>
public sealed record ProblemExport(
    string Id,
    string Type,
    string Title,
    int Status,
    bool Recoverable,
    JsonNode Schema,
    IReadOnlyList<ProblemEndpoint> Endpoints);
