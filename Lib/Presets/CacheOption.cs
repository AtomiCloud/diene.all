namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// A single named cache connection. Cache is Dragonfly: RAM-backed and EPHEMERAL — losing it
/// must never lose durable state. Redis protocol.
/// </summary>
/// <remarks>
/// C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go. Distinct
/// from <see cref="KvOption" /> despite the identical connection fields, because the
/// durability contract differs.
/// </remarks>
public sealed class CacheOption : RedisConnectionOption
{
    /// <summary>The config key the whole block binds to.</summary>
    public const string Key = "Cache";
}

/// <summary>Validates one named cache connection.</summary>
public sealed class CacheOptionValidator : RedisConnectionOptionValidator<CacheOption>;

/// <summary>Validates the whole <c>cache</c> block: UPPERCASE keys, valid entries.</summary>
public sealed class CacheBlockValidator : KeyedBlockValidator<CacheBlock, CacheOption>
{
    /// <summary>Builds the rules.</summary>
    public CacheBlockValidator() : base(new CacheOptionValidator()) { }
}
