using System.Collections.Immutable;

namespace AtomiCloud.Diene.Interfaces;

/// <summary>
/// One process invocation requested through <see cref="ITerminal"/>. Argument and
/// environment collections are snapshotted at construction, so a command value
/// cannot change under an implementation that already accepted it.
/// </summary>
public sealed class TerminalCommand
{
    /// <summary>Creates a command from caller-owned inputs.</summary>
    /// <param name="executable">The program to launch.</param>
    /// <param name="args">The program arguments, excluding the executable.</param>
    /// <param name="workingDirectory">The working directory, or absent to keep the host one.</param>
    /// <param name="environment">Process-specific environment overrides.</param>
    /// <param name="includeParentEnvironment">Whether host variables are inherited.</param>
    /// <param name="runInShell">Whether to execute through an implementation-selected shell.</param>
    public TerminalCommand(
        string executable,
        IEnumerable<string>? args = null,
        string? workingDirectory = null,
        IEnumerable<KeyValuePair<string, string>>? environment = null,
        bool includeParentEnvironment = true,
        bool runInShell = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executable);
        Executable = executable;
        Args = args is null ? [] : [.. args];
        WorkingDirectory = Option.FromNullable(workingDirectory);
        Environment = environment is null
            ? ImmutableSortedDictionary<string, string>.Empty.WithComparers(StringComparer.Ordinal)
            : ImmutableSortedDictionary.CreateRange(StringComparer.Ordinal, environment);
        IncludeParentEnvironment = includeParentEnvironment;
        RunInShell = runInShell;
    }

    /// <summary>The program to launch.</summary>
    public string Executable { get; }

    /// <summary>The program arguments, excluding the executable.</summary>
    public IReadOnlyList<string> Args { get; }

    /// <summary>The working directory, absent when the host one is kept.</summary>
    public Option<string> WorkingDirectory { get; }

    /// <summary>Process-specific environment overrides, ordered by key.</summary>
    public IReadOnlyDictionary<string, string> Environment { get; }

    /// <summary>Whether host environment variables are inherited.</summary>
    public bool IncludeParentEnvironment { get; }

    /// <summary>Whether the command runs through an implementation-selected shell.</summary>
    public bool RunInShell { get; }

    /// <summary>Renders the command as its executable and arguments.</summary>
    public override string ToString() => string.Join(' ', [Executable, .. Args]);
}

/// <summary>Captured output from a completed terminal invocation.</summary>
/// <param name="ExitCode">The child process exit code.</param>
/// <param name="Stdout">Captured standard output.</param>
/// <param name="Stderr">Captured standard error.</param>
public readonly record struct TerminalOutput(int ExitCode, string Stdout, string Stderr)
{
    /// <summary>Whether the child exited with code zero.</summary>
    public bool Succeeded => ExitCode == 0;
}

/// <summary>
/// A process-execution boundary. A non-zero child exit code is a SUCCESSFUL
/// <see cref="TerminalOutput"/>; only a launch failure is a
/// <see cref="SeamErrors.LaunchFailed"/> failure value.
/// </summary>
public interface ITerminal
{
    /// <summary>Executes a command and captures its output.</summary>
    Task<Result<TerminalOutput, SeamError>> Run(
        TerminalCommand command,
        CancellationToken cancellationToken = default);
}
