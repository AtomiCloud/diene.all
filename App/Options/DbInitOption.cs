using AtomiCloud.Diene.CoreUtils;
using FluentValidation;

namespace AtomiCloud.DotnetBase.App.Options;

/// <summary>
/// The <c>db_init:</c> block. Every step of the one-shot initialisation job is a flag, so the
/// same artifact serves a first install (create the bucket, migrate, seed) and an upgrade
/// (migrate only) without a second image.
/// </summary>
public sealed class DbInitOption
{
    /// <summary>Configuration key this block binds to.</summary>
    public const string Key = "DbInit";

    /// <summary>Whether to check every declared dependency is reachable before doing any work.</summary>
    public bool CheckReachability { get; set; } = true;

    /// <summary>Whether to create the configured storage bucket when it does not exist.</summary>
    public bool CreateBucket { get; set; }

    /// <summary>Whether to apply outstanding EF Core migrations.</summary>
    public bool Migrate { get; set; } = true;

    /// <summary>Whether to seed preset data. Seeding is always seed-if-not-exists.</summary>
    public bool Seed { get; set; } = true;

    /// <summary>How long each reachability check may take, as an ISO 8601 duration.</summary>
    public string ReachabilityTimeout { get; set; } = "PT30S";

    /// <summary>How long to keep retrying a dependency before declaring it unreachable.</summary>
    public string ReachabilityWindow { get; set; } = "PT2M";
}

/// <summary>Validates <see cref="DbInitOption"/> on the final merged configuration layer.</summary>
public sealed class DbInitOptionValidator : AbstractValidator<DbInitOption>
{
    /// <summary>Declares the block's rules.</summary>
    public DbInitOptionValidator()
    {
        this.RuleFor(x => x.ReachabilityTimeout)
            .Must(BeAPositiveWireDuration)
            .WithMessage("db_init:reachability_timeout must be a positive ISO 8601 duration");

        this.RuleFor(x => x.ReachabilityWindow)
            .Must(BeAPositiveWireDuration)
            .WithMessage("db_init:reachability_window must be a positive ISO 8601 duration");

        this.RuleFor(x => x)
            .Must(x => Both(x.ReachabilityTimeout, x.ReachabilityWindow, (timeout, window) => timeout <= window))
            .WithMessage("db_init:reachability_timeout must not exceed db_init:reachability_window");
    }

    private static bool BeAPositiveWireDuration(string value) =>
        Wire.ParseDuration(value).Match(duration => duration > TimeSpan.Zero, _ => false);

    private static bool Both(string left, string right, Func<TimeSpan, TimeSpan, bool> predicate) => Wire
        .ParseDuration(left)
        .Match(
            l => Wire.ParseDuration(right).Match(r => predicate(l, r), _ => false),
            _ => false);
}
