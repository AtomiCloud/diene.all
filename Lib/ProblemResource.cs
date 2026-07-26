using System.Text.Json.Nodes;

namespace AtomiCloud.Diene.Problems;

/// <summary>Identifies one platform/service/landscape/version Problem CR row.</summary>
public sealed record ProblemResourceIdentity(
    string Platform,
    string Service,
    string Landscape,
    string Version);

/// <summary>A Kubernetes Problem custom resource.</summary>
public sealed record ProblemResource(
    string ApiVersion,
    string Kind,
    ProblemResourceMetadata Metadata,
    ProblemResourceSpec Spec);

/// <summary>Problem CR object metadata.</summary>
public sealed record ProblemResourceMetadata(string Name, string Namespace);

/// <summary>Problem CR specification.</summary>
public sealed record ProblemResourceSpec(
    string Platform,
    string Service,
    string Landscape,
    string Version,
    IReadOnlyList<ProblemResourceEntry> Problems);

/// <summary>One typed problem in a Problem CR.</summary>
public sealed record ProblemResourceEntry(
    string Id,
    string Type,
    string Title,
    int Status,
    bool Recoverable,
    JsonNode Schema,
    IReadOnlyList<ProblemEndpoint> Endpoints);
