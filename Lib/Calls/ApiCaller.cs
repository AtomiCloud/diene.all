using System.Text.Json;
using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.Calls;

/// <summary>The default <see cref="IApiCaller" />, classifying every outcome of a wrapped call.</summary>
/// <param name="config">The validated upstream configuration.</param>
/// <param name="typeUris">The builder that turns this engine's problem ids into type URIs.</param>
public sealed class ApiCaller(ApiEngineConfig config, IProblemTypeUriBuilder typeUris) : IApiCaller
{
    private readonly ApiEngineConfig _config = config ?? throw new ArgumentNullException(nameof(config));

    private readonly IProblemTypeUriBuilder _typeUris =
        typeUris ?? throw new ArgumentNullException(nameof(typeUris));

    /// <inheritdoc />
    public async Task<Result<T, Problem>> Call<T>(
        ServiceAddress address,
        Func<CancellationToken, Task<T>> call,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(call);

        using var scope = new ApiCallScope();
        try
        {
            var value = await call(cancellationToken).ConfigureAwait(false);
            return Result.Ok<T, Problem>(value);
        }
        catch (Exception exception) when (exception is not OutOfMemoryException)
        {
            return Result.Err<T, Problem>(Classify(address, scope.Capture, exception));
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, Problem>> Call(
        ServiceAddress address,
        Func<CancellationToken, Task> call,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(call);
        return Call<Unit>(
            address,
            async token =>
            {
                await call(token).ConfigureAwait(false);
                return new Unit();
            },
            cancellationToken);
    }

    private Problem Classify(ServiceAddress address, ApiCallCapture capture, Exception exception)
    {
        var upstream = address.ToString();

        // A token that could not be acquired is an authentication failure, not a transport
        // one. The auth handler carries the typed problem out on the exception so it is not
        // flattened into "the upstream was unreachable", which would send a caller looking
        // at the wrong service.
        if (exception is DomainProblemException carried)
        {
            return Envelope(carried.Problem);
        }

        var rescuable = _config.Find(address).Match(upstreamConfig => upstreamConfig.RescueRoutingEnabled, () => false);
        return ApiResponseClassifier.Classify(
            upstream,
            capture.Failure,
            Math.Max(capture.Attempts, 1),
            rescuable,
            Reason(exception, upstream),
            _typeUris);
    }

    private static string Reason(Exception exception, string upstream) => exception switch
    {
        // A cancelled task is how both a client timeout and a caller's own cancellation
        // arrive, and the two are worth telling apart in the detail even though they are the
        // same problem type.
        TaskCanceledException { InnerException: TimeoutException } =>
            $"The call to upstream '{upstream}' timed out.",
        OperationCanceledException => $"The call to upstream '{upstream}' was cancelled.",

        // A status on the exception means the exchange COMPLETED and the upstream answered. Saying
        // "could not be reached" here would be a true-sounding sentence about the wrong thing, and
        // it is what sends someone to check network policy for a contract mismatch.
        HttpRequestException { StatusCode: not null } answered =>
            $"Upstream '{upstream}' answered with status {(int)answered.StatusCode.Value}.",
        HttpRequestException => $"Upstream '{upstream}' could not be reached.",
        _ => $"The call to upstream '{upstream}' failed with {exception.GetType().Name}.",
    };

    private Problem Envelope(IDomainProblem problem) =>
        new()
        {
            Type = _typeUris.Build(problem.Version, problem.Id).AbsoluteUri,
            Title = problem.Title,
            Status = StatusOf(problem),
            Detail = problem.Detail,
            Recoverable = false,
            Data = JsonSerializer.SerializeToNode(problem, problem.GetType(), AtomiJson.DefaultOptions),
        };

    /// <summary>
    /// The status for a problem the engine did not originate.
    /// </summary>
    /// <remarks>
    /// Deliberately not read from a catalog: this engine renders a failure for a caller to
    /// branch on, it does not write an HTTP response. A consumer that surfaces this problem
    /// over HTTP renders it through the problems library, which is where its own catalog
    /// status applies.
    /// </remarks>
    private static int StatusOf(IDomainProblem problem) => problem is Unauthenticated ? 401 : 403;
}
