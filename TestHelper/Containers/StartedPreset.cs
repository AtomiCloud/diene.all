using DotNet.Testcontainers.Containers;

namespace AtomiCloud.Diene.StandardConfig.TestHelper.Containers;

/// <summary>
/// A started preset container together with the config block that reaches it.
/// </summary>
/// <remarks>
/// The block is the point. Booting a container is easy; the part every consumer would
/// otherwise re-derive is translating the container's mapped host and port into a schema-valid
/// keyed block, so an integration test is just "start the helper, register the presets, run
/// the real code".
/// </remarks>
/// <typeparam name="TBlock">The preset's named block type.</typeparam>
/// <typeparam name="TEntry">The preset's entry type.</typeparam>
public sealed class StartedPreset<TBlock, TEntry> : IAsyncDisposable
    where TBlock : Dictionary<string, TEntry>, new()
{
    private readonly IContainer _container;

    internal StartedPreset(IContainer container, string key, TEntry entry)
    {
        _container = container;
        Key = key;
        Entry = entry;
        Block = new TBlock { [key] = entry };
    }

    /// <summary>The UPPERCASE connection key the block is registered under.</summary>
    public string Key { get; }

    /// <summary>The single resolved entry.</summary>
    public TEntry Entry { get; }

    /// <summary>The keyed block <c>{ KEY: entry }</c>, valid against the preset's validator.</summary>
    public TBlock Block { get; }

    /// <summary>
    /// The block flattened into configuration keys, ready for <c>AddInMemoryCollection</c> or
    /// an env-style layer.
    /// </summary>
    public IReadOnlyDictionary<string, string?> ConfigurationValues(string blockKey) =>
        PresetConfiguration.Flatten(blockKey, Key, Entry!);

    /// <summary>Stops and removes the container.</summary>
    public async ValueTask DisposeAsync() => await _container.DisposeAsync().ConfigureAwait(false);
}
