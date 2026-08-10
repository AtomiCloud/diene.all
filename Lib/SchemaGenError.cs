namespace AtomiCloud.Diene.Config;

/// <summary>Why a schema could not be written or did not match what is on disk.</summary>
public enum SchemaGenFault
{
    /// <summary>The schema file could not be read or written.</summary>
    Io,

    /// <summary>The expected schema file is not there at all.</summary>
    Missing,

    /// <summary>The file on disk differs from the schema the registry generates — drift.</summary>
    Drift,
}

/// <summary>
/// A schema generation or verification failure, returned rather than thrown so a CI drift
/// check is an ordinary branch instead of an exception handler.
/// </summary>
/// <param name="Fault">Which kind of failure this is.</param>
/// <param name="Path">The schema file the operation targeted.</param>
/// <param name="Detail">A human-readable explanation.</param>
public sealed record SchemaGenError(SchemaGenFault Fault, string Path, string Detail);
