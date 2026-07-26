using FluentValidation;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// The Redis-protocol connection shape shared by the <c>cache</c> and <c>kv</c> presets.
/// </summary>
/// <remarks>
/// <para>
/// Cache (Dragonfly) and kv (Upstash, or the snapshot-durable Dragonfly realization) both
/// speak the Redis protocol, so their CONNECTION fields are identical. They stay two
/// SEPARATE presets under two distinct root keys because their DURABILITY contracts differ:
/// cache is RAM-backed and ephemeral, kv is persistent. Sharing this base type is an
/// implementation detail — the cache-may-not-be-relabeled-KV rule holds at the block
/// boundary, which is where it matters.
/// </para>
/// <para>
/// <see cref="Password" /> is a secret — blank-in-yaml, injected per landscape (R14/M33).
/// </para>
/// </remarks>
public abstract class RedisConnectionOption
{
    /// <summary>Hostname of the Redis-protocol endpoint.</summary>
    public string Host { get; set; } = "";

    /// <summary>TCP port.</summary>
    public int Port { get; set; }

    /// <summary>Secret — blank-in-yaml, injected per landscape (R14/M33).</summary>
    public string Password { get; set; } = "";

    /// <summary>Logical database index (Redis <c>SELECT</c>).</summary>
    public int Db { get; set; }

    /// <summary>Whether to require TLS on the connection.</summary>
    public bool Tls { get; set; }
}

/// <summary>Validates one named Redis-protocol connection, whatever preset owns it.</summary>
/// <typeparam name="T">The owning preset's entry type.</typeparam>
public class RedisConnectionOptionValidator<T> : AbstractValidator<T>
    where T : RedisConnectionOption
{
    /// <summary>Builds the rules.</summary>
    public RedisConnectionOptionValidator()
    {
        RuleFor(x => x.Host).NotEmpty();
        RuleFor(x => x.Port).InclusiveBetween(1, 65535);
        RuleFor(x => x.Db).GreaterThanOrEqualTo(0);
    }
}
