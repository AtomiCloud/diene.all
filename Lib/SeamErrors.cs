namespace AtomiCloud.Diene.Interfaces;

/// <summary>
/// The canonical seam failure catalog. Every implementation of a seam — the
/// shipped in-memory mocks, host-backed adapters, and downstream libraries such
/// as <c>AtomiCloud.Diene.Otel</c> — reports failures through these factories so
/// consumers can match one stable id per failure mode.
/// </summary>
public static class SeamErrors
{
    /// <summary>The argument was absent, empty, or structurally unusable.</summary>
    public static SeamError InvalidArgument(SeamKind seam, string name, string detail) =>
        new(seam, "invalid_argument", "Invalid argument", detail, [new("argument", name)]);

    /// <summary>No filesystem entry exists at the path.</summary>
    public static SeamError NotFound(string path) =>
        new(SeamKind.Vfs, "not_found", "Entry not found", $"No entry exists at '{path}'.", [new("path", path)]);

    /// <summary>An entry already exists at the path.</summary>
    public static SeamError AlreadyExists(string path) =>
        new(
            SeamKind.Vfs,
            "already_exists",
            "Entry already exists",
            $"An entry already exists at '{path}'.",
            [new("path", path)]);

    /// <summary>The path names a file where a directory was required.</summary>
    public static SeamError NotADirectory(string path) =>
        new(
            SeamKind.Vfs,
            "not_a_directory",
            "Entry is not a directory",
            $"'{path}' is not a directory.",
            [new("path", path)]);

    /// <summary>A non-recursive delete was refused because the directory has children.</summary>
    public static SeamError DirectoryNotEmpty(string path) =>
        new(
            SeamKind.Vfs,
            "directory_not_empty",
            "Directory is not empty",
            $"'{path}' still has entries; retry with a recursive delete.",
            [new("path", path)]);

    /// <summary>The seam operation failed in its host runtime.</summary>
    public static SeamError IoFailure(SeamKind seam, string operation, string detail) =>
        new(seam, "io_failure", "Host operation failed", detail, [new("operation", operation)]);

    /// <summary>The environment variable could not be read.</summary>
    public static SeamError EnvironmentUnavailable(string name, string detail) =>
        new(
            SeamKind.System,
            "environment_unavailable",
            "Environment variable unavailable",
            detail,
            [new("variable", name)]);

    /// <summary>The child process could not be launched. A non-zero exit code is NOT this error.</summary>
    public static SeamError LaunchFailed(string executable, string detail) =>
        new(
            SeamKind.Terminal,
            "launch_failed",
            "Process launch failed",
            detail,
            [new("executable", executable)]);

    /// <summary>The sink refused or failed to accept the record.</summary>
    public static SeamError EmitFailed(SeamKind seam, string detail) =>
        new(seam, "emit_failed", "Emit failed", detail);

    /// <summary>The operation was cancelled before it completed.</summary>
    public static SeamError Cancelled(SeamKind seam, string operation) =>
        new(
            seam,
            "cancelled",
            "Operation cancelled",
            $"'{operation}' was cancelled before it completed.",
            [new("operation", operation)]);

    /// <summary>A wire value did not conform to its C0 format.</summary>
    public static SeamError InvalidWire(string field, string value) =>
        new(
            SeamKind.Logging,
            "invalid_wire",
            "Invalid wire value",
            $"'{value}' is not a valid {field} wire value.",
            [new("field", field), new("value", value)]);

    /// <summary>The IANA timezone id is not installed on the host.</summary>
    public static SeamError UnknownTimeZone(string id, string detail) =>
        new(SeamKind.Logging, "unknown_time_zone", "Unknown IANA timezone", detail, [new("timeZone", id)]);
}
