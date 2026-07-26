namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>The resolved <c>postgres</c> block: named connections, keyed UPPERCASE.</summary>
/// <remarks>
/// <para>
/// Each preset gets a NAMED block type rather than a bare
/// <c>Dictionary&lt;string, TEntry&gt;</c>, for two reasons. Consumers resolve
/// <c>IOptions&lt;PostgresBlock&gt;</c>, which reads as what it is. And the config lib's schema
/// registry renders a block through NJsonSchema by reference: an anonymous dictionary type has
/// no definition to point at, so registering one produces a dangling <c>$ref</c> and schema
/// generation fails outright. A named type lands in <c>definitions</c> and resolves.
/// </para>
/// </remarks>
public sealed class PostgresBlock : Dictionary<string, PostgresOption>;

/// <summary>The resolved <c>cache</c> block: RAM-backed, ephemeral connections.</summary>
public sealed class CacheBlock : Dictionary<string, CacheOption>;

/// <summary>The resolved <c>kv</c> block: persistent connections.</summary>
public sealed class KvBlock : Dictionary<string, KvOption>;

/// <summary>The resolved <c>storage</c> block: S3-compatible endpoints.</summary>
public sealed class StorageBlock : Dictionary<string, StorageOption>;
