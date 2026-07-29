using AtomiCloud.DotnetBase.App.StartUp;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// Thin bootstrap. It resolves the run mode and hands off; all composition lives in
/// <see cref="Server"/> and <see cref="DbInit"/>, so this file never grows.
/// </summary>
public static class Program
{
    /// <summary>Process entry point.</summary>
    /// <param name="args">The process arguments.</param>
    /// <returns>The process exit code.</returns>
    public static Task<int> Main(string[] args)
    {
        if (!RunModeSelection.TryResolve(args, out var mode, out var rejected))
        {
            Console.Error.WriteLine(
                $"unknown run mode '{rejected}'; expected " +
                $"'{RunModeSelection.ServerArgument}' or '{RunModeSelection.DbInitArgument}'");
            return Task.FromResult(2);
        }

        return mode switch
        {
            RunMode.DbInit => DbInit.RunAsync(args),
            _ => Server.RunAsync(args),
        };
    }
}
