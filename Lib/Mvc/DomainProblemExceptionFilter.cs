using System.Diagnostics;
using AtomiCloud.Diene.Problems;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.Diene.ServerEngine.Mvc;

/// <summary>
/// The MVC exception filter that renders a <see cref="DomainProblemException" /> as this
/// package's RFC 9457 envelope.
/// </summary>
/// <remarks>
/// <para>
/// The published Problems package already registers an <c>IExceptionHandler</c> for the same
/// exception. That handler sits in the terminal middleware, which only sees an exception MVC
/// did not deal with; it also renders through <c>IProblemDetailsService</c>, so its output
/// depends on the host's content negotiation. This filter runs INSIDE the MVC pipeline, which
/// is where a controller's failure actually surfaces, and writes the envelope itself. Keeping
/// it here is why no server wiring has to leak into the Problems package.
/// </para>
/// <para>
/// Anything that is not a domain problem is left untouched — an unhandled
/// <see cref="NullReferenceException" /> must not be dressed up as a typed domain failure, or
/// a real defect becomes indistinguishable from an expected refusal.
/// </para>
/// </remarks>
public sealed class DomainProblemExceptionFilter(
    IProblemCatalog catalog,
    IProblemTypeUriBuilder typeUris,
    ILogger<DomainProblemExceptionFilter> logger) : IAsyncExceptionFilter
{
    private readonly IProblemCatalog _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
    private readonly IProblemTypeUriBuilder _typeUris = typeUris ?? throw new ArgumentNullException(nameof(typeUris));

    private readonly ILogger<DomainProblemExceptionFilter> _logger =
        logger ?? throw new ArgumentNullException(nameof(logger));

    /// <inheritdoc />
    public Task OnExceptionAsync(ExceptionContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (context.Exception is not DomainProblemException domain) return Task.CompletedTask;

        var problem = domain.Problem;
        var traceId = Activity.Current?.Id ?? context.HttpContext.TraceIdentifier;
        var envelope = ProblemEnvelope.FromDomain(
            problem,
            this._catalog,
            this._typeUris,
            context.HttpContext.Request.Path.Value ?? "/",
            traceId);

        this._logger.LogDebug(
            "Rendered domain problem {ProblemVersion}/{ProblemId} as {Status} for {TraceId}",
            problem.Version,
            problem.Id,
            envelope.Status,
            traceId);

        context.Result = ProblemEnvelope.ToResult(envelope);
        context.ExceptionHandled = true;
        return Task.CompletedTask;
    }
}
