using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config.Yaml;

/// <summary>A YAML file layer, keyed canonically per C0 §3.</summary>
/// <remarks>
/// Own provider rather than a third-party YAML package: key normalization has to happen
/// INSIDE the provider for a snake-cased YAML key to bind a Pascal option property, and a
/// dependency we would have to wrap and patch costs more than the parser we own.
/// </remarks>
internal sealed class YamlConfigurationSource : FileConfigurationSource
{
    public override IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        EnsureDefaults(builder);
        return new YamlConfigurationProvider(this);
    }
}

/// <summary>Loads a single YAML layer into flat, canonically-keyed configuration data.</summary>
internal sealed class YamlConfigurationProvider(YamlConfigurationSource source) : FileConfigurationProvider(source)
{
    public override void Load(Stream stream) => Data = YamlConfigurationParser.Parse(stream);
}
