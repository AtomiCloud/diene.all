using System.Security;

namespace AtomiCloud.Diene.Interfaces.App.Adapters;

/// <summary>
/// The host-backed reference <see cref="ISystem"/>. It lives in the non-packable
/// demo consumer, not in the shipped library: under the S33 boundary the
/// interfaces package declares seams and ships mocks, while every concrete host
/// adapter belongs to the consumer that owns its runtime. It exists here so the
/// integration tier can run the shipped contract suite against a REAL host.
/// </summary>
public sealed class HostSystem : ISystem
{
    /// <inheritdoc />
    public Result<Option<string>, SeamError> Environment(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return SeamErrors.InvalidArgument(SeamKind.System, nameof(name), "The variable name must not be blank.");
        }

        try
        {
            return Result.Ok<Option<string>, SeamError>(
                Option.FromNullable(global::System.Environment.GetEnvironmentVariable(name)));
        }
        catch (SecurityException exception)
        {
            return SeamErrors.EnvironmentUnavailable(name, exception.Message);
        }
    }

    /// <inheritdoc />
    public Result<string, SeamError> CurrentDirectory()
    {
        try
        {
            return Result.Ok<string, SeamError>(Directory.GetCurrentDirectory());
        }
        catch (IOException exception)
        {
            return SeamErrors.IoFailure(SeamKind.System, "currentDirectory", exception.Message);
        }
    }

    /// <inheritdoc />
    public Result<DateTimeOffset, SeamError> NowUtc() => Result.Ok<DateTimeOffset, SeamError>(DateTimeOffset.UtcNow);

    /// <inheritdoc />
    public async Task<Result<Unit, SeamError>> Delay(TimeSpan duration, CancellationToken cancellationToken = default)
    {
        try
        {
            await Task.Delay(duration, cancellationToken).ConfigureAwait(false);
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (OperationCanceledException)
        {
            return SeamErrors.Cancelled(SeamKind.System, "delay");
        }
    }
}
