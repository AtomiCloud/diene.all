using System.ComponentModel;
using System.Diagnostics;

namespace AtomiCloud.Diene.Interfaces.App.Adapters;

/// <summary>
/// The host-backed reference <see cref="ITerminal"/> over <c>System.Diagnostics</c>.
/// A non-zero exit code is a successful <see cref="TerminalOutput"/>; only a launch
/// failure becomes <see cref="SeamErrors.LaunchFailed"/>.
/// </summary>
public sealed class HostTerminal : ITerminal
{
    /// <inheritdoc />
    public async Task<Result<TerminalOutput, SeamError>> Run(
        TerminalCommand command,
        CancellationToken cancellationToken = default)
    {
        if (command is null)
        {
            return SeamErrors.InvalidArgument(SeamKind.Terminal, nameof(command), "The command must not be null.");
        }

        var info = new ProcessStartInfo(command.Executable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var argument in command.Args) info.ArgumentList.Add(argument);
        if (command.WorkingDirectory.IsSome(out var workingDirectory)) info.WorkingDirectory = workingDirectory;
        info.Environment.Clear();
        if (command.IncludeParentEnvironment)
        {
            foreach (var entry in Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>())
            {
                info.Environment[(string)entry.Key] = entry.Value as string ?? string.Empty;
            }
        }

        foreach (var entry in command.Environment) info.Environment[entry.Key] = entry.Value;

        try
        {
            using var process = Process.Start(info)
                ?? throw new InvalidOperationException("The host returned no process handle.");
            var stdout = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderr = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            return Result.Ok<TerminalOutput, SeamError>(new TerminalOutput(
                process.ExitCode,
                await stdout.ConfigureAwait(false),
                await stderr.ConfigureAwait(false)));
        }
        catch (Win32Exception exception)
        {
            return SeamErrors.LaunchFailed(command.Executable, exception.Message);
        }
        catch (InvalidOperationException exception)
        {
            return SeamErrors.LaunchFailed(command.Executable, exception.Message);
        }
        catch (OperationCanceledException)
        {
            return SeamErrors.Cancelled(SeamKind.Terminal, "run");
        }
    }
}
