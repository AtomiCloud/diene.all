using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config.TestHelper;

/// <summary>
/// An in-memory stand-in for one YAML layer, keyed exactly the way the real YAML provider
/// keys it.
/// </summary>
/// <remarks>
/// A consumer testing merge behaviour needs layers, not files. Handing them
/// <c>AddInMemoryCollection</c> instead would key the layer differently from the provider it
/// is standing in for, so a snake-cased fake would stop overriding a Pascal-cased real layer
/// and the test would prove the opposite of production.
/// </remarks>
public sealed class FakeConfigLayer : IConfigurationSource
{
    private readonly Dictionary<string, string?> _values = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Sets one key in this layer. The key may be written in any C0 spelling.</summary>
    public FakeConfigLayer Set(string key, string? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        _values[ConfigKey.Path(key)] = value;
        return this;
    }

    /// <summary>Sets many keys in this layer.</summary>
    public FakeConfigLayer SetAll(IEnumerable<KeyValuePair<string, string?>> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        foreach (var (key, value) in values) Set(key, value);
        return this;
    }

    /// <summary>
    /// Declares a key with no value — the blank-in-yaml secrets convention, where the key
    /// exists in the layer and its value is expected to arrive from the environment.
    /// </summary>
    public FakeConfigLayer Declare(string key) => Set(key, null);

    /// <summary>The canonical keys and values this layer contributes.</summary>
    public IReadOnlyDictionary<string, string?> Values => _values;

    IConfigurationProvider IConfigurationSource.Build(IConfigurationBuilder builder) =>
        new FakeConfigProvider(_values);

    private sealed class FakeConfigProvider(IReadOnlyDictionary<string, string?> values) : ConfigurationProvider
    {
        public override void Load() =>
            Data = new Dictionary<string, string?>(values, StringComparer.OrdinalIgnoreCase);
    }
}
