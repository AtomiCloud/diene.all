using System.Globalization;
using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.Diene.StandardConfig.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// The network-free half of the demo: layer the YAML, bind the presets, and prove startup
/// validation is doing real work.
/// </summary>
/// <remarks>
/// Every line it prints is an assertion in disguise, which is what makes it a useful probe
/// target: if precedence, keyed binding, secret injection, or fail-fast validation regresses,
/// the run stops printing rather than printing something subtly wrong.
/// </remarks>
public static class PresetDemo
{
    /// <summary>The landscape whose sparse overlay the demo applies.</summary>
    public const string Landscape = "lapras";

    /// <summary>Runs every step and returns what it observed.</summary>
    public static IReadOnlyList<string> Run()
    {
        var lines = new List<string>();

        // Layer 1+2: base YAML, then the sparse landscape overlay. The overlay names only the
        // kv port, and that is the only value it may change.
        var layered = ConfigComposition.Build(Landscape, []);
        using var layeredProvider = ConfigComposition.Provider(layered);

        var cache = Block<CacheBlock>(layeredProvider).Named("MAIN");
        var kv = Block<KvBlock>(layeredProvider).Named("MAIN");
        lines.Add(Line($"cache MAIN stays on the base port {cache.Port}, kv MAIN takes the overlay port {kv.Port}"));

        // Layer 3: the environment override, LAST. Secrets are declared blank in YAML and
        // arrive only here — the same path as any other key.
        var withSecrets = ConfigComposition.Build(Landscape, new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["ATOMI_POSTGRES__MAIN__PASSWORD"] = "injected-secret",
            ["ATOMI_STORAGE__MAIN__ACCESS_KEY_ID"] = "injected-key",
        });
        using var secretProvider = ConfigComposition.Provider(withSecrets);

        var postgres = Block<PostgresBlock>(secretProvider).Named("MAIN");
        var storage = Block<StorageBlock>(secretProvider).Named("MAIN");
        lines.Add(Line(
            $"postgres MAIN password arrived from the environment ({postgres.Password.Length} chars), " +
            $"storage MAIN access key too ({storage.AccessKeyId.Length} chars)"));

        // Keyed multi-instance: a SECOND named pool is data, never code.
        var twoPools = ConfigComposition.Build(Landscape, new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["ATOMI_POSTGRES__REPLICA__HOST"] = "replica.internal",
            ["ATOMI_POSTGRES__REPLICA__PORT"] = "5432",
            ["ATOMI_POSTGRES__REPLICA__DATABASE"] = "app",
            ["ATOMI_POSTGRES__REPLICA__USERNAME"] = "app",
            ["ATOMI_POSTGRES__REPLICA__SSL"] = "true",
            ["ATOMI_POSTGRES__REPLICA__POOL__MIN"] = "0",
            ["ATOMI_POSTGRES__REPLICA__POOL__MAX"] = "4",
        });
        using var twoPoolProvider = ConfigComposition.Provider(twoPools);

        var pools = Block<PostgresBlock>(twoPoolProvider);
        lines.Add(Line($"postgres now serves {pools.Count} named pools: {string.Join(", ", pools.Keys.Order(StringComparer.Ordinal))}"));

        // Fail-fast: a malformed pool name has to surface at ValidateOnStart, not at first use
        // long after boot.
        lines.Add(Line($"a malformed pool name is rejected at startup: {RejectedPoolName()}"));

        // A validator is an ordinary object: a consumer can run one directly, with no host and
        // no configuration, which is how you unit-test a block you built by hand.
        lines.Add(Line($"validators run standalone: {StandaloneValidation()}"));

        // A missing connection fails loudly, naming the connections that DO exist, rather than
        // resolving to null somewhere far away from the typo that caused it.
        lines.Add(Line($"a missing connection names the known keys: {MissingConnection()}"));

        // Composing NO presets registers nothing at all — the flag set is honoured exactly, and
        // registering the four one at a time reaches the same place.
        lines.Add(Line($"composing None registers {RegisteredBlockCount(StandardConfigPreset.None)} blocks, " +
                       $"{ConfigComposition.Presets} registers {RegisteredBlockCount(ConfigComposition.Presets)}, " +
                       $"one-at-a-time registers {ChainedRegistrationCount()}"));

        // The production factory builds its own S3 client from the block. Links are pure, so
        // this reaches nothing over the network.
        using var tigris = S3BlockStorage.Create(new StorageOption
        {
            Endpoint = "https://fly.storage.tigris.dev",
            Region = "auto",
            Bucket = "app",
            ForcePathStyle = false,
        });
        lines.Add(Line($"virtual-hosted link: {tigris.GetLink("avatars/user-1.png")}"));

        // The composed root schema is the union of every registered block.
        var registry = ConfigComposition.Registry();
        var blocks = registry is ConfigSchemaRegistry concrete ? concrete.Blocks.Count : 0;
        lines.Add(Line($"root schema composes {blocks} blocks"));

        return lines;
    }

    /// <summary>
    /// Builds one block per preset by hand and runs its validator directly — no host, no
    /// configuration, no DI.
    /// </summary>
    public static string StandaloneValidation()
    {
        var postgres = new PostgresBlock
        {
            ["MAIN"] = new PostgresOption
            {
                Host = "localhost",
                Port = 5432,
                Database = "app",
                Username = "app",
                Password = "",
                Ssl = false,
                Pool = new PostgresPoolOption { Min = 0, Max = 10 },
            },
        };
        var cache = new CacheBlock
        {
            ["MAIN"] = new CacheOption { Host = "localhost", Port = 6379, Password = "", Db = 0, Tls = false },
        };
        var kv = new KvBlock
        {
            ["MAIN"] = new KvOption { Host = "localhost", Port = 6380, Password = "", Db = 0, Tls = true },
        };
        var storage = new StorageBlock
        {
            ["MAIN"] = new StorageOption
            {
                Endpoint = "http://localhost:9000",
                Region = "us-east-1",
                Bucket = "app",
                AccessKeyId = "",
                SecretAccessKey = "",
                ForcePathStyle = true,
            },
        };

        var valid =
            new PostgresBlockValidator().Validate(postgres).IsValid &&
            new CacheBlockValidator().Validate(cache).IsValid &&
            new KvBlockValidator().Validate(kv).IsValid &&
            new StorageBlockValidator().Validate(storage).IsValid;

        // ...and the same validator rejects an empty entry, so it is doing real work.
        var empty = new CacheBlockValidator().Validate(new CacheBlock { ["MAIN"] = new CacheOption() });

        return $"4 hand-built blocks valid = {valid}, empty entry produces {empty.Errors.Count} failures";
    }

    /// <summary>The message a keyed lookup produces when the connection is absent.</summary>
    public static string MissingConnection()
    {
        var block = new KvBlock { ["main"] = new KvOption { Host = "localhost", Port = 6380 } };

        try
        {
            _ = block.Named("ANALYTICS");
            return "NOT REJECTED — this is a bug";
        }
        catch (StandardConfigException exception)
        {
            return exception.Message;
        }
    }

    /// <summary>How many blocks a given preset selection registers.</summary>
    public static int RegisteredBlockCount(StandardConfigPreset presets) =>
        BlockCount(new ServiceCollection().AddStandardConfigs(presets));

    /// <summary>
    /// The same four blocks, registered through the per-preset entry points a service that
    /// composes only some of them would reach for.
    /// </summary>
    public static int ChainedRegistrationCount() =>
        BlockCount(new ServiceCollection()
            .AddPostgresPreset()
            .AddCachePreset()
            .AddKvPreset()
            .AddStoragePreset());

    private static int BlockCount(IServiceCollection services)
    {
        var descriptor = services.FirstOrDefault(entry => entry.ServiceType == typeof(IConfigSchemaRegistry));
        return descriptor?.ImplementationInstance is ConfigSchemaRegistry registry ? registry.Blocks.Count : 0;
    }

    /// <summary>The validation message a misspelled pool name produces.</summary>
    public static string RejectedPoolName()
    {
        var configuration = ConfigComposition.Build(Landscape, new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["ATOMI_CACHE__MY@POOL__HOST"] = "localhost",
            ["ATOMI_CACHE__MY@POOL__PORT"] = "6379",
        });

        using var provider = ConfigComposition.Provider(configuration);

        try
        {
            _ = Block<CacheBlock>(provider);
            return "NOT REJECTED — this is a bug";
        }
        catch (OptionsValidationException exception)
        {
            return exception.Failures.First();
        }
    }

    private static TBlock Block<TBlock>(IServiceProvider provider)
        where TBlock : class =>
        provider.GetRequiredService<IOptions<TBlock>>().Value;

    private static string Line(string text) => string.Create(CultureInfo.InvariantCulture, $"• {text}");
}
