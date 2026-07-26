namespace AtomiCloud.Diene.Config;

/// <summary>
/// Writes and verifies the generated config schema. Dev- and CI-time only.
/// </summary>
/// <remarks>
/// Deliberately NOT a boot-time step: writing files at startup inside a chiseled container is
/// a wart the seed carried and this port drops. A <c>pls</c> task calls
/// <see cref="WriteSchema" />; CI calls <see cref="VerifySchema" /> and reds on drift.
/// </remarks>
public static class ConfigSchemaGen
{
    /// <summary>Renders the registry to <paramref name="path" />, creating the directory if needed.</summary>
    public static Result<Unit, SchemaGenError> WriteSchema(IConfigSchemaRegistry registry, string path)
    {
        ArgumentNullException.ThrowIfNull(registry);
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        try
        {
            var directory = System.IO.Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            File.WriteAllText(path, Document(registry));
            return Result.Ok<Unit, SchemaGenError>(new Unit());
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return Result.Err<Unit, SchemaGenError>(new SchemaGenError(SchemaGenFault.Io, path, exception.Message));
        }
    }

    /// <summary>Reds when <paramref name="path" /> is absent or has drifted from the registry.</summary>
    public static Result<Unit, SchemaGenError> VerifySchema(IConfigSchemaRegistry registry, string path)
    {
        ArgumentNullException.ThrowIfNull(registry);
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        if (!File.Exists(path))
            return Result.Err<Unit, SchemaGenError>(new SchemaGenError(
                SchemaGenFault.Missing,
                path,
                "The generated schema is missing. Run the schema generation task and commit the result."));

        string actual;
        try
        {
            actual = File.ReadAllText(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return Result.Err<Unit, SchemaGenError>(new SchemaGenError(SchemaGenFault.Io, path, exception.Message));
        }

        return string.Equals(Normalize(actual), Normalize(Document(registry)), StringComparison.Ordinal)
            ? Result.Ok<Unit, SchemaGenError>(new Unit())
            : Result.Err<Unit, SchemaGenError>(new SchemaGenError(
                SchemaGenFault.Drift,
                path,
                "The generated schema has drifted from the registered option blocks. Regenerate and commit it."));
    }

    private static string Document(IConfigSchemaRegistry registry) =>
        registry.ToJsonSchema().ReplaceLineEndings("\n").TrimEnd() + "\n";

    /// <summary>Line endings are a checkout artifact, not drift.</summary>
    private static string Normalize(string document) => document.ReplaceLineEndings("\n").TrimEnd();
}
