using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.ServerEngine.Mvc;

/// <summary>
/// Builds the RFC 9457 envelope this package writes, and the MVC result that carries it.
/// </summary>
/// <remarks>
/// The envelope is serialized here with the published wire options rather than handed to a
/// content negotiator, so the bytes on the wire do not depend on how a consumer happened to
/// configure MVC's JSON. An error response is the one payload a caller reads when everything
/// else has already gone wrong; it should not be the one whose shape is least controlled.
/// </remarks>
public static class ProblemEnvelope
{
    /// <summary>The media type every problem response is written as.</summary>
    public const string ContentType = "application/problem+json";

    /// <summary>The type URI used when a problem is not registered in the catalog.</summary>
    public const string UnregisteredType = "about:blank";

    /// <summary>
    /// Builds the envelope for a typed domain problem, resolving its status, type URI, and
    /// recoverability from the catalog the consumer registered.
    /// </summary>
    public static Problem FromDomain(
        IDomainProblem problem,
        IProblemCatalog catalog,
        IProblemTypeUriBuilder typeUris,
        string instance,
        string traceId)
    {
        ArgumentNullException.ThrowIfNull(problem);
        ArgumentNullException.ThrowIfNull(catalog);
        ArgumentNullException.ThrowIfNull(typeUris);

        var descriptor = catalog.Find(problem.Version, problem.Id);
        var registered = descriptor.IsSome(out var entry) && entry.Type == problem.GetType();

        return new Problem
        {
            Type = registered ? typeUris.Build(problem.Version, problem.Id).AbsoluteUri : UnregisteredType,
            Title = problem.Title,
            Status = catalog.StatusOf(problem),
            Detail = problem.Detail,
            Instance = instance,
            Recoverable = registered && entry!.Recoverable,
            Data = JsonSerializer.SerializeToNode(problem, problem.GetType(), AtomiJson.DefaultOptions),
            Extensions = TraceExtension(traceId),
        };
    }

    /// <summary>
    /// Builds the envelope for a transport-level refusal that is not a catalog problem —
    /// a rejected webhook signature, an unsupported media type, a malformed envelope.
    /// </summary>
    /// <remarks>
    /// These deliberately do not go through the catalog. The statuses C0 §11 fixes are
    /// security-relevant, and resolving them through a registry a consumer must remember to
    /// populate would let a missing registration silently turn a 401 into a 500.
    /// </remarks>
    public static Problem FromProtocol(int status, string title, string detail, string instance, string traceId) =>
        new()
        {
            Type = UnregisteredType,
            Title = title,
            Status = status,
            Detail = detail,
            Instance = instance,
            Recoverable = false,
            Extensions = TraceExtension(traceId),
        };

    /// <summary>Renders an envelope as the problem+json result MVC should write.</summary>
    public static ContentResult ToResult(Problem envelope)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        return new ContentResult
        {
            StatusCode = envelope.Status,
            ContentType = ContentType,
            Content = JsonSerializer.Serialize(envelope, AtomiJson.DefaultOptions),
        };
    }

    private static Dictionary<string, JsonElement> TraceExtension(string traceId) =>
        new(StringComparer.Ordinal) { ["traceId"] = JsonSerializer.SerializeToElement(traceId) };
}
