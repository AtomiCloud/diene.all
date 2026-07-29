using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.Diene.Problems;

/// <summary>Renders DomainProblemException values through ASP.NET Core's ProblemDetails service.</summary>
public sealed class DomainProblemExceptionHandler(
    IProblemDetailsService problemDetails,
    IProblemCatalog catalog) : IExceptionHandler
{
    private readonly IProblemDetailsService _problemDetails =
        problemDetails ?? throw new ArgumentNullException(nameof(problemDetails));
    private readonly IProblemCatalog _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));

    /// <inheritdoc />
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(httpContext);
        if (exception is not DomainProblemException domainException) return false;

        httpContext.Items[ProblemHttpContext.DomainProblemKey] = domainException.Problem;
        httpContext.Response.StatusCode = _catalog.StatusOf(domainException.Problem);
        await _problemDetails.WriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = new ProblemDetails(),
        });
        return true;
    }
}
