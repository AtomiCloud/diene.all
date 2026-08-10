using FluentValidation;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>Connection-pool sizing for a named Postgres connection.</summary>
public sealed class PostgresPoolOption
{
    /// <summary>Minimum pooled connections held open.</summary>
    public int Min { get; set; }

    /// <summary>Maximum pooled connections.</summary>
    public int Max { get; set; }
}

/// <summary>
/// A single named Postgres connection.
/// </summary>
/// <remarks>
/// <para>
/// Provider-agnostic: Neon, CNPG, and a local container all speak this shape. Which
/// provider serves a landscape is the environment matrix's business, never the connection
/// block's.
/// </para>
/// <para>
/// <see cref="Password" /> is a secret — blank in YAML (R14), injected per landscape through
/// the env-override tier (M33: a blank value is unset, so the base-YAML placeholder never
/// survives the landscape's real secret).
/// </para>
/// <para>
/// C0-FROZEN (c0-contracts.md §3): this key set matches the bun, dotnet, and go
/// standard-config libraries key-for-key. Do not drift the keys.
/// </para>
/// </remarks>
public sealed class PostgresOption
{
    /// <summary>The config key the whole block binds to.</summary>
    public const string Key = "Postgres";

    /// <summary>Hostname of the Postgres endpoint.</summary>
    public string Host { get; set; } = "";

    /// <summary>TCP port.</summary>
    public int Port { get; set; }

    /// <summary>Database name.</summary>
    public string Database { get; set; } = "";

    /// <summary>Role/user name.</summary>
    public string Username { get; set; } = "";

    /// <summary>Secret — blank-in-yaml, injected per landscape (R14/M33).</summary>
    public string Password { get; set; } = "";

    /// <summary>Whether to require TLS on the connection.</summary>
    public bool Ssl { get; set; }

    /// <summary>Connection-pool sizing.</summary>
    public PostgresPoolOption Pool { get; set; } = new();
}

/// <summary>Validates one named Postgres connection.</summary>
public sealed class PostgresOptionValidator : AbstractValidator<PostgresOption>
{
    /// <summary>Builds the rules.</summary>
    public PostgresOptionValidator()
    {
        RuleFor(x => x.Host).NotEmpty();
        RuleFor(x => x.Port).InclusiveBetween(1, 65535);
        RuleFor(x => x.Database).NotEmpty();
        RuleFor(x => x.Username).NotEmpty();
        RuleFor(x => x.Pool).NotNull();
        RuleFor(x => x.Pool.Min).GreaterThanOrEqualTo(0).When(x => x.Pool is not null);
        RuleFor(x => x.Pool.Max).GreaterThanOrEqualTo(1).When(x => x.Pool is not null);
        RuleFor(x => x.Pool)
            .Must(pool => pool.Max >= pool.Min)
            .When(x => x.Pool is not null)
            .WithMessage("pool.max must be greater than or equal to pool.min");
    }
}

/// <summary>Validates the whole <c>postgres</c> block: UPPERCASE keys, valid entries.</summary>
public sealed class PostgresBlockValidator : KeyedBlockValidator<PostgresBlock, PostgresOption>
{
    /// <summary>Builds the rules.</summary>
    public PostgresBlockValidator() : base(new PostgresOptionValidator()) { }
}
