namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// A deterministic <see cref="ITerminal"/> scripted per executable. An executable
/// that was never programmed reports <see cref="SeamErrors.LaunchFailed"/>, which
/// is exactly how a host terminal answers an unresolvable program.
/// </summary>
public sealed class InMemoryTerminal : ITerminal
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, Result<TerminalOutput, SeamError>> _scripts = new(StringComparer.Ordinal);
    private readonly List<TerminalCommand> _commands = [];

    /// <summary>The commands this seam was asked to run, in call order.</summary>
    public IReadOnlyList<TerminalCommand> Commands
    {
        get
        {
            lock (_gate) return [.. _commands];
        }
    }

    /// <summary>Programs the output an executable returns.</summary>
    public void Program(string executable, TerminalOutput output)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executable);
        lock (_gate) _scripts[executable] = Result.Ok<TerminalOutput, SeamError>(output);
    }

    /// <summary>Programs a launch failure for an executable.</summary>
    public void Fail(string executable, SeamError error)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executable);
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _scripts[executable] = Result.Err<TerminalOutput, SeamError>(error);
    }

    /// <inheritdoc />
    public Task<Result<TerminalOutput, SeamError>> Run(
        TerminalCommand command,
        CancellationToken cancellationToken = default)
    {
        if (command is null)
        {
            return Task.FromResult(Result.Err<TerminalOutput, SeamError>(
                SeamErrors.InvalidArgument(SeamKind.Terminal, nameof(command), "The command must not be null.")));
        }

        lock (_gate)
        {
            _commands.Add(command);
            return Task.FromResult(_scripts.TryGetValue(command.Executable, out var scripted)
                ? scripted
                : Result.Err<TerminalOutput, SeamError>(SeamErrors.LaunchFailed(
                    command.Executable,
                    $"'{command.Executable}' was never programmed on this terminal seam.")));
        }
    }
}
