namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// A single named kv connection. kv is PERSISTENT — Upstash in the cloud, and a
/// snapshot-durable Dragonfly instance where that is what the landscape runs. Redis protocol.
/// </summary>
/// <remarks>
/// A snapshot-durable instance is a DISTINCT deployment, not a relabelled
/// <see cref="CacheOption" />: pointing kv at the cache instance silently trades durability
/// for nothing, which is exactly the mistake the two-preset split exists to make impossible.
/// C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go.
/// </remarks>
public sealed class KvOption : RedisConnectionOption
{
    /// <summary>The config key the whole block binds to.</summary>
    public const string Key = "Kv";
}

/// <summary>Validates one named kv connection.</summary>
public sealed class KvOptionValidator : RedisConnectionOptionValidator<KvOption>;

/// <summary>Validates the whole <c>kv</c> block: UPPERCASE keys, valid entries.</summary>
public sealed class KvBlockValidator : KeyedBlockValidator<KvBlock, KvOption>
{
    /// <summary>Builds the rules.</summary>
    public KvBlockValidator() : base(new KvOptionValidator()) { }
}
