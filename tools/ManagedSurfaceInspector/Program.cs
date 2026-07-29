using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text.Json;

if (args.Length != 3 || args[0] != "verify")
{
    Console.Error.WriteLine("usage: ManagedSurfaceInspector verify <assembly.dll> <contract.json>");
    return 2;
}

var assemblyPath = Path.GetFullPath(args[1]);
var contractPath = Path.GetFullPath(args[2]);
if (!File.Exists(assemblyPath) || !File.Exists(contractPath))
{
    Console.Error.WriteLine("assembly and contract must both exist");
    return 3;
}

var contract = JsonSerializer.Deserialize<SurfaceContract>(
    File.ReadAllText(contractPath),
    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
if (contract is null || string.IsNullOrWhiteSpace(contract.Name))
{
    Console.Error.WriteLine("surface contract is malformed");
    return 4;
}

using var stream = File.OpenRead(assemblyPath);
using var pe = new PEReader(stream);
if (!pe.HasMetadata)
{
    Console.Error.WriteLine($"assembly has no managed metadata: {assemblyPath}");
    return 5;
}

var surfaces = ReadSurface(pe.GetMetadataReader());
if (!VerifySpecs("positive-control", contract.PositiveControls, surfaces))
{
    Console.Error.WriteLine("positive control failed; refusing to trust subsequent absence checks");
    return 40;
}

foreach (var mapping in contract.SemanticMappings)
{
    if (!VerifySpecs($"semantic:{mapping.Goal}", mapping.SatisfiedBy, surfaces)) return 41;
}

if (!VerifySpecs("required", contract.Required, surfaces)) return 42;

Console.WriteLine(
    $"PASS\t{contract.Name}\tpositive={contract.PositiveControls.Length}" +
    $"\tsemantic={contract.SemanticMappings.Length}\trequired={contract.Required.Length}");
return 0;

static Dictionary<string, Surface> ReadSurface(MetadataReader reader)
{
    var surfaces = new Dictionary<string, Surface>(StringComparer.Ordinal);
    foreach (var typeHandle in reader.TypeDefinitions)
    {
        var definition = reader.GetTypeDefinition(typeHandle);
        if (!IsPublicType(definition.Attributes)) continue;

        var name = reader.GetString(definition.Name);
        var ns = reader.GetString(definition.Namespace);
        var fullName = string.IsNullOrEmpty(ns) ? name : $"{ns}.{name}";
        var surface = new Surface();

        foreach (var methodHandle in definition.GetMethods())
        {
            var method = reader.GetMethodDefinition(methodHandle);
            if (IsPublicMethod(method.Attributes)) surface.Methods.Add(reader.GetString(method.Name));
        }

        foreach (var fieldHandle in definition.GetFields())
        {
            var field = reader.GetFieldDefinition(fieldHandle);
            if (IsPublicField(field.Attributes)) surface.Fields.Add(reader.GetString(field.Name));
        }

        foreach (var propertyHandle in definition.GetProperties())
        {
            var property = reader.GetPropertyDefinition(propertyHandle);
            var accessors = property.GetAccessors();
            var getter = !accessors.Getter.IsNil &&
                         IsPublicMethod(reader.GetMethodDefinition(accessors.Getter).Attributes);
            var setter = !accessors.Setter.IsNil &&
                         IsPublicMethod(reader.GetMethodDefinition(accessors.Setter).Attributes);
            if (getter || setter) surface.Properties.Add(reader.GetString(property.Name));
        }

        surfaces[fullName] = surface;
    }

    return surfaces;
}

static bool VerifySpecs(
    string phase,
    IEnumerable<string> specs,
    IReadOnlyDictionary<string, Surface> surfaces)
{
    var passed = true;
    foreach (var spec in specs)
    {
        var present = Evaluate(spec, surfaces);
        Console.WriteLine($"{(present ? "PRESENT" : "MISSING")}\t{phase}\t{spec}");
        passed &= present;
    }

    return passed;
}

static bool Evaluate(string spec, IReadOnlyDictionary<string, Surface> surfaces)
{
    if (spec.Length < 3 || spec[1] != ':') return false;

    var kind = spec[0];
    var body = spec[2..];
    if (kind == 'T') return surfaces.ContainsKey(body);

    var split = body.Split("::", 2, StringSplitOptions.None);
    if (split.Length != 2 || !surfaces.TryGetValue(split[0], out var surface)) return false;
    return kind switch
    {
        'M' => surface.Methods.Contains(split[1]),
        'P' => surface.Properties.Contains(split[1]),
        'F' => surface.Fields.Contains(split[1]),
        _ => false,
    };
}

static bool IsPublicType(TypeAttributes attributes)
{
    var visibility = attributes & TypeAttributes.VisibilityMask;
    return visibility is TypeAttributes.Public or TypeAttributes.NestedPublic;
}

static bool IsPublicMethod(MethodAttributes attributes) =>
    (attributes & MethodAttributes.MemberAccessMask) == MethodAttributes.Public;

static bool IsPublicField(FieldAttributes attributes) =>
    (attributes & FieldAttributes.FieldAccessMask) == FieldAttributes.Public;

sealed class SurfaceContract
{
    public string Name { get; init; } = string.Empty;

    public string[] PositiveControls { get; init; } = [];

    public SemanticMapping[] SemanticMappings { get; init; } = [];

    public string[] Required { get; init; } = [];
}

sealed class SemanticMapping
{
    public string Goal { get; init; } = string.Empty;

    public string[] SatisfiedBy { get; init; } = [];
}

sealed class Surface
{
    internal HashSet<string> Methods { get; } = new(StringComparer.Ordinal);

    internal HashSet<string> Properties { get; } = new(StringComparer.Ordinal);

    internal HashSet<string> Fields { get; } = new(StringComparer.Ordinal);
}
