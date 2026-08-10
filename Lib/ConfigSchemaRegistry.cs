using NJsonSchema;
using NJsonSchema.Generation;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// Collects the option blocks a service composes into its root config schema.
/// </summary>
/// <remarks>
/// A service's root schema is not written by hand and is not owned by any single lib: each
/// engine lib exports its OWN block next to the code that reads it, the service registers one
/// line per block, and this registry assembles the union. That assembled schema is what the
/// generated <c>$schema</c> pointer on every config YAML resolves to.
/// </remarks>
public interface IConfigSchemaRegistry
{
    /// <summary>Registers the option type bound at <paramref name="key" /> as a root block.</summary>
    void Register<T>(string key);

    /// <summary>Renders every registered block into one JSON schema document.</summary>
    string ToJsonSchema();
}

/// <summary>The default registry: an order-independent set of blocks rendered through NJsonSchema.</summary>
public sealed class ConfigSchemaRegistry : IConfigSchemaRegistry
{
    private readonly SortedDictionary<string, Type> _blocks = new(StringComparer.Ordinal);

    /// <inheritdoc />
    public void Register<T>(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        _blocks[key] = typeof(T);
    }

    /// <summary>The registered blocks, keyed by their config key.</summary>
    public IReadOnlyDictionary<string, Type> Blocks => _blocks;

    /// <inheritdoc />
    public string ToJsonSchema()
    {
        var root = new JsonSchema
        {
            Title = "Service configuration",
            Description = "Composed from every option block the service registers.",
            Type = JsonObjectType.Object,
            AllowAdditionalProperties = true,
        };

        // The generated pointer C0 requires as the first line of every config YAML is part of
        // the document the schema describes, so the schema has to permit it explicitly.
        root.Properties["$schema"] = new JsonSchemaProperty
        {
            Type = JsonObjectType.String,
            Description = "Pointer to this schema.",
        };

        var settings = new SystemTextJsonSchemaGeneratorSettings { SchemaType = SchemaType.JsonSchema };
        var generator = new JsonSchemaGenerator(settings);
        var resolver = new JsonSchemaResolver(root, settings);

        foreach (var (key, type) in _blocks)
        {
            var block = generator.Generate(type, resolver);
            root.Properties[key] = new JsonSchemaProperty { Reference = block };
        }

        return root.ToJson();
    }
}
