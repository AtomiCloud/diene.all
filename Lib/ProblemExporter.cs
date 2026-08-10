using System.ComponentModel;
using System.Reflection;
using System.Text.Json.Nodes;
using System.Text.Json.Schema;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.Diene.Problems;

/// <summary>Exports catalog entries using the .NET JSON contract as the schema source of truth.</summary>
public sealed class ProblemExporter(IProblemCatalog catalog, IProblemTypeUriBuilder typeUris) : IProblemExporter
{
    private static readonly JsonSchemaExporterOptions ExporterOptions = new()
    {
        TreatNullObliviousAsNonNullable = true,
        TransformSchemaNode = AddDescription,
    };

    private readonly IProblemCatalog _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
    private readonly IProblemTypeUriBuilder _typeUris = typeUris ?? throw new ArgumentNullException(nameof(typeUris));

    /// <inheritdoc />
    public ProblemExport Export(ProblemDescriptor descriptor)
    {
        ArgumentNullException.ThrowIfNull(descriptor);
        if (!_catalog.All.Any(candidate => ReferenceEquals(candidate, descriptor)))
            throw new ArgumentException("Only descriptors belonging to this catalog can be exported.", nameof(descriptor));

        var schema = JsonSchemaExporter.GetJsonSchemaAsNode(
            AtomiJson.DefaultOptions,
            descriptor.Type,
            ExporterOptions);
        return new ProblemExport(
            descriptor.Id,
            _typeUris.Build(descriptor.Version, descriptor.Id).AbsoluteUri,
            descriptor.Title,
            descriptor.Status,
            descriptor.Recoverable,
            schema,
            descriptor.Endpoints);
    }

    /// <inheritdoc />
    public IReadOnlyList<ProblemExport> ExportAll() =>
        Array.AsReadOnly([.. _catalog.All.Select(Export)]);

    private static JsonNode AddDescription(JsonSchemaExporterContext context, JsonNode schema)
    {
        var attributeProvider = context.PropertyInfo?.AttributeProvider;
        var description = attributeProvider?
            .GetCustomAttributes(typeof(DescriptionAttribute), true)
            .OfType<DescriptionAttribute>()
            .FirstOrDefault();
        description ??= context.TypeInfo.Type.GetCustomAttribute<DescriptionAttribute>();

        if (description is not null && schema is JsonObject schemaObject)
            schemaObject["description"] = description.Description;
        return schema;
    }
}
