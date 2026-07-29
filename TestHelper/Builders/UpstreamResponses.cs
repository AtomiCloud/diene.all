using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.Diene.ApiEngine.TestHelper.Builders;

/// <summary>
/// Response bodies for every branch of the classification matrix, so a consumer's tests
/// exercise the same shapes this engine is specified against rather than shapes invented per
/// test.
/// </summary>
/// <remarks>
/// Built through the platform serializer rather than written as string literals, so a change to
/// the wire contract reaches these fixtures instead of leaving them describing an older one.
/// </remarks>
public static class UpstreamResponses
{
    /// <summary>An RFC 9457 problem envelope as another Diene service would emit it.</summary>
    public static string Problem(
        string type,
        string title,
        int status,
        string detail,
        bool recoverable = false,
        JsonNode? data = null)
    {
        var envelope = new JsonObject
        {
            ["type"] = type,
            ["title"] = title,
            ["status"] = status,
            ["detail"] = detail,
            ["recoverable"] = recoverable,
        };
        if (data is not null) envelope["data"] = data;
        return envelope.ToJsonString(AtomiJson.DefaultOptions);
    }

    /// <summary>
    /// A problem envelope wrapped by an upstream that puts its errors under a member.
    /// </summary>
    /// <remarks>
    /// A real shape, not a hypothetical: gateways and older services routinely wrap an error
    /// document, and a classifier that only recognises a bare envelope reports these as
    /// unparseable failures.
    /// </remarks>
    public static string NestedProblem(string wrapper, string type, string title, int status, string detail)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(wrapper);
        var inner = JsonNode.Parse(Problem(type, title, status, detail));
        return new JsonObject { [wrapper] = inner }.ToJsonString(AtomiJson.DefaultOptions);
    }

    /// <summary>
    /// Well-formed JSON that is NOT a problem envelope — the shape a service with a different
    /// error contract returns.
    /// </summary>
    public static string NonProblemJson(string message, int code) =>
        new JsonObject { ["message"] = message, ["code"] = code }.ToJsonString(AtomiJson.DefaultOptions);

    /// <summary>A successful payload for the happy path.</summary>
    public static string Payload<T>(T value) => JsonSerializer.Serialize(value, AtomiJson.DefaultOptions);
}
