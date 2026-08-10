namespace AtomiCloud.Diene.Interfaces;

/// <summary>The kind of a virtual filesystem entry.</summary>
public enum VfsEntryType
{
    /// <summary>A regular file.</summary>
    File,

    /// <summary>A directory.</summary>
    Directory,

    /// <summary>A symbolic link.</summary>
    Link,
}

/// <summary>Metadata for one virtual filesystem entry.</summary>
public sealed class VfsEntry
{
    /// <summary>Creates an entry, normalizing the modification time to UTC.</summary>
    /// <param name="path">The implementation-owned opaque path.</param>
    /// <param name="type">The entry kind.</param>
    /// <param name="size">The entry size in bytes.</param>
    /// <param name="modifiedAt">The modification time, when the implementation has one.</param>
    public VfsEntry(string path, VfsEntryType type, long size, DateTimeOffset? modifiedAt = null)
    {
        ArgumentNullException.ThrowIfNull(path);
        Path = path;
        Type = type;
        Size = size;
        ModifiedAt = modifiedAt.HasValue
            ? Option.Some(modifiedAt.Value.ToUniversalTime())
            : Option.None<DateTimeOffset>();
    }

    /// <summary>The implementation-owned opaque path.</summary>
    public string Path { get; }

    /// <summary>The entry kind.</summary>
    public VfsEntryType Type { get; }

    /// <summary>The entry size in bytes.</summary>
    public long Size { get; }

    /// <summary>The modification time in UTC, absent when the implementation has none.</summary>
    public Option<DateTimeOffset> ModifiedAt { get; }

    /// <summary>Renders the entry as <c>type path (size)</c>.</summary>
    public override string ToString() => $"{SeamWire.Name(Type)} {Path} ({Size})";
}

/// <summary>Options for a write operation.</summary>
/// <param name="CreateParents">Creates missing parent directories before writing.</param>
public readonly record struct VfsWriteOptions(bool CreateParents = false);

/// <summary>Options for a list operation.</summary>
/// <param name="Recursive">Includes descendants instead of only direct children.</param>
public readonly record struct VfsListOptions(bool Recursive = false);

/// <summary>Options for a directory create or delete operation.</summary>
/// <param name="Recursive">Creates missing ancestors, or deletes descendants.</param>
public readonly record struct VfsDirectoryOptions(bool Recursive = false);

/// <summary>
/// A portable virtual filesystem boundary. Paths are opaque strings;
/// normalization and sandbox policy belong to the implementation. No method
/// throws for a filesystem condition — a missing entry is a
/// <see cref="SeamErrors.NotFound"/> failure value.
/// </summary>
public interface IVfs
{
    /// <summary>Reports whether the path names an entry.</summary>
    Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default);

    /// <summary>Reads a file as bytes.</summary>
    Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(string path, CancellationToken cancellationToken = default);

    /// <summary>Reads a UTF-8 text file.</summary>
    Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default);

    /// <summary>Writes bytes to a file, replacing any existing content.</summary>
    Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default);

    /// <summary>Writes UTF-8 text to a file, replacing any existing content.</summary>
    Task<Result<Unit, SeamError>> WriteText(
        string path,
        string content,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default);

    /// <summary>Lists the entries below a directory.</summary>
    Task<Result<IReadOnlyList<VfsEntry>, SeamError>> List(
        string path,
        VfsListOptions options = default,
        CancellationToken cancellationToken = default);

    /// <summary>Creates a directory.</summary>
    Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default);

    /// <summary>Removes a file or directory.</summary>
    Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default);
}
