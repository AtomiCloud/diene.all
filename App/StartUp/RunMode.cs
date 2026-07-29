namespace AtomiCloud.DotnetBase.App.StartUp;

/// <summary>The two things this artifact can be. There is no cron mode (R20).</summary>
public enum RunMode
{
    /// <summary>Serve HTTP. The default when no mode is named.</summary>
    Server,

    /// <summary>Run the one-shot initialisation path and exit. Migration lives in here.</summary>
    DbInit,
}

/// <summary>Resolves the run mode from the process arguments.</summary>
public static class RunModeSelection
{
    /// <summary>The argument that selects the one-shot initialisation path.</summary>
    public const string DbInitArgument = "db-init";

    /// <summary>The argument that explicitly selects the HTTP server.</summary>
    public const string ServerArgument = "server";

    /// <summary>
    /// Reads the mode from the first non-flag argument. An unrecognised mode is an error rather
    /// than a silent fall back to the server: a typo in a Job's args must not start a web host.
    /// </summary>
    /// <param name="args">The raw process arguments.</param>
    /// <param name="mode">The resolved mode when this returns <see langword="true"/>.</param>
    /// <param name="rejected">The unrecognised argument when this returns <see langword="false"/>.</param>
    /// <returns><see langword="true"/> when the arguments name a known mode.</returns>
    public static bool TryResolve(string[] args, out RunMode mode, out string rejected)
    {
        rejected = string.Empty;
        mode = RunMode.Server;

        var named = args.FirstOrDefault(argument => !argument.StartsWith('-'));
        if (named is null) return true;

        switch (named)
        {
            case ServerArgument:
                mode = RunMode.Server;
                return true;
            case DbInitArgument:
                mode = RunMode.DbInit;
                return true;
            default:
                rejected = named;
                return false;
        }
    }
}
