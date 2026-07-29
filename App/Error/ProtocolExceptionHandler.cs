using System.Diagnostics;
using System.Text.Json;
using AtomiCloud.Diene.ServerEngine.Module;
using AtomiCloud.Diene.ServerEngine.Mvc;
using Microsoft.AspNetCore.Diagnostics;

namespace AtomiCloud.DotnetBase.App.Error;

/// <summary>
/// Renders anything the domain handler declines as the SAME RFC 9457 envelope.
/// </summary>
/// <remarks>
/// <para>
/// <c>DomainProblemExceptionHandler</c> only owns <c>DomainProblemException</c>. Without this,
/// a raw exception falls through to ASP.NET's built-in <c>ProblemDetails</c> — an
/// <c>rfc9110</c> type URI, no <c>data</c> extension — which puts a SECOND error contract on
/// the wire beside RFC 9457. A client written against the Diene envelope parses every typed
/// problem correctly and then hits a differently-shaped 500.
/// </para>
/// <para>
/// The library ships <see cref="ProblemEnvelope.FromProtocol"/> precisely for the non-domain
/// case — it is what the server engine's own webhook protocol refusals are built from — so
/// this calls it rather than inventing a second envelope shape.
/// </para>
/// <para>
/// Registered AFTER the domain handler: ASP.NET runs handlers in registration order and stops
/// at the first that returns <see langword="true"/>, so the typed path keeps priority and this
/// only ever sees what that path declined.
/// </para>
/// </remarks>
/// <param name="logger">Sink for the unhandled exception, which must not reach the client.</param>
public sealed class ProtocolExceptionHandler(ILogger<ProtocolExceptionHandler> logger) : IExceptionHandler
{
    private static readonly JsonSerializerOptions Wire = CreateWireOptions();

    /// <inheritdoc />
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(httpContext);

        // The detail deliberately carries nothing from the exception: a stack trace or an
        // internal message on the wire is an information leak, and the log is where it belongs.
        logger.LogError(exception, "unhandled exception; rendering a protocol-level problem");

        var envelope = ProblemEnvelope.FromProtocol(
            StatusCodes.Status500InternalServerError,
            "Internal Server Error",
            "The request could not be completed.",
            httpContext.Request.Path.Value ?? "/",
            Activity.Current?.Id ?? httpContext.TraceIdentifier);

        httpContext.Response.StatusCode = envelope.Status;
        httpContext.Response.ContentType = ProblemEnvelope.ContentType;
        await httpContext.Response
            .WriteAsync(JsonSerializer.Serialize(envelope, Wire), cancellationToken)
            .ConfigureAwait(false);

        return true;
    }

    private static JsonSerializerOptions CreateWireOptions()
    {
        var options = new JsonSerializerOptions();
        ServerEngineServiceCollectionExtensions.ApplyWireContract(options);
        return options;
    }
}
