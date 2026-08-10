using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.DotnetBase.App;

/// <summary>One note as the demo upstream serves it.</summary>
/// <param name="Id">The note identifier.</param>
/// <param name="Body">The note body.</param>
public sealed record NoteView(string Id, string Body);

/// <summary>
/// The error documents the demo upstream serves.
/// </summary>
/// <remarks>
/// Written here rather than taken from the shipped TestHelper: these are the SERVER's own error
/// documents, and the demo models a real service, which does not take a test dependency in
/// production. That the two look similar is the point — the engine is being checked against
/// bodies produced independently of the fixtures its own tests use.
/// </remarks>
public static class Fixtures
{
    /// <summary>An RFC 9457 problem envelope.</summary>
    public static string Problem(string type, string title, int status, string detail) =>
        new JsonObject
        {
            ["type"] = type,
            ["title"] = title,
            ["status"] = status,
            ["detail"] = detail,
            ["recoverable"] = false,
        }.ToJsonString(AtomiJson.DefaultOptions);

    /// <summary>A problem envelope wrapped under a member, as a gateway would return it.</summary>
    public static string NestedProblem(string wrapper, string type, string title, int status, string detail) =>
        new JsonObject
        {
            [wrapper] = JsonNode.Parse(Problem(type, title, status, detail)),
        }.ToJsonString(AtomiJson.DefaultOptions);

    /// <summary>Well-formed JSON that is not a problem envelope.</summary>
    public static string NonProblemJson(string message, int code) =>
        new JsonObject
        {
            ["message"] = message,
            ["code"] = code,
        }.ToJsonString(AtomiJson.DefaultOptions);
}
