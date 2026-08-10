using System.Diagnostics;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.ServerEngine.Mvc;

/// <summary>
/// The MVC base every Diene service controller derives from. It turns a
/// <c>Result&lt;T, IDomainProblem&gt;</c> into an action result and lets the
/// exception-to-Problem filter render every failure.
/// </summary>
/// <remarks>
/// <para>
/// Failures are raised as <see cref="DomainProblemException" /> rather than returned as a
/// result. That looks indirect, and it is deliberate: it gives the service exactly ONE place
/// that renders an error, so a controller cannot accidentally emit a second error shape, and
/// a problem thrown from deep inside a domain call renders identically to one a controller
/// produced itself.
/// </para>
/// <para>
/// This base is deliberately NOT marked <c>[ApiController]</c>. That attribute installs its
/// own automatic 400 for model-state failures, which would emit ASP.NET's
/// <c>ValidationProblemDetails</c> shape alongside this package's envelope — two error
/// contracts in one service. Without it, a malformed body reaches the action as a null model
/// and the action returns a typed problem through the same single path.
/// </para>
/// </remarks>
public abstract class AtomiController : ControllerBase
{
    /// <summary>
    /// Gets the correlation identifier for the current request: the ambient activity id when
    /// tracing is running, and the connection-scoped trace identifier otherwise.
    /// </summary>
    protected string TraceId => Activity.Current?.Id ?? this.HttpContext.TraceIdentifier;

    /// <summary>Returns 200 with the value, or raises the typed problem for the filter to render.</summary>
    protected ActionResult<T> Resolve<T>(Result<T, IDomainProblem> result)
    {
        if (result.IsFailure(out var problem)) throw problem.ToException();
        return this.Ok(result.Get());
    }

    /// <summary>Awaits the operation, then resolves it exactly as the synchronous overload does.</summary>
    protected async Task<ActionResult<T>> ResolveAsync<T>(Task<Result<T, IDomainProblem>> pending)
    {
        ArgumentNullException.ThrowIfNull(pending);
        return this.Resolve(await pending.ConfigureAwait(false));
    }

    /// <summary>Returns 204 on success, or raises the typed problem for the filter to render.</summary>
    protected ActionResult ResolveEmpty(Result<Unit, IDomainProblem> result)
    {
        if (result.IsFailure(out var problem)) throw problem.ToException();
        return this.NoContent();
    }

    /// <summary>Awaits the operation, then resolves it exactly as the synchronous overload does.</summary>
    protected async Task<ActionResult> ResolveEmptyAsync(Task<Result<Unit, IDomainProblem>> pending)
    {
        ArgumentNullException.ThrowIfNull(pending);
        return this.ResolveEmpty(await pending.ConfigureAwait(false));
    }
}
