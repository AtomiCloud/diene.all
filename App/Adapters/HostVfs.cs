using System.Text;

namespace AtomiCloud.Diene.Interfaces.App.Adapters;

/// <summary>
/// The host-backed reference <see cref="IVfs"/> over <c>System.IO</c>. It converts
/// every filesystem condition into a <see cref="SeamError"/> value and never lets
/// an exception escape, which is the S33 rule the shipped contract suite checks.
/// </summary>
public sealed class HostVfs : IVfs
{
    /// <inheritdoc />
    public Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Guarded<bool>(path, "exists", cancellationToken, full => File.Exists(full) || Directory.Exists(full)));

    /// <inheritdoc />
    public async Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(
        string path,
        CancellationToken cancellationToken = default)
    {
        var guarded = Guarded<string>(path, "readBytes", cancellationToken, full => full);
        if (guarded.IsFailure(out var error)) return Result.Err<ReadOnlyMemory<byte>, SeamError>(error);
        var full = guarded.Get();
        if (!File.Exists(full)) return SeamErrors.NotFound(full);
        try
        {
            return Result.Ok<ReadOnlyMemory<byte>, SeamError>(
                await File.ReadAllBytesAsync(full, cancellationToken).ConfigureAwait(false));
        }
        catch (IOException exception)
        {
            return SeamErrors.IoFailure(SeamKind.Vfs, "readBytes", exception.Message);
        }
        catch (OperationCanceledException)
        {
            return SeamErrors.Cancelled(SeamKind.Vfs, "readBytes");
        }
    }

    /// <inheritdoc />
    public async Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default)
    {
        var bytes = await ReadBytes(path, cancellationToken).ConfigureAwait(false);
        return bytes.Map(value => Encoding.UTF8.GetString(value.Span));
    }

    /// <inheritdoc />
    public async Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default)
    {
        var guarded = Guarded<string>(path, "writeBytes", cancellationToken, full => full);
        if (guarded.IsFailure(out var error)) return Result.Err<Unit, SeamError>(error);
        var full = guarded.Get();
        var parent = Path.GetDirectoryName(full);
        if (!string.IsNullOrEmpty(parent) && !Directory.Exists(parent))
        {
            if (!options.CreateParents) return SeamErrors.NotFound(Normalize(parent));
            Directory.CreateDirectory(parent);
        }

        try
        {
            await File.WriteAllBytesAsync(full, bytes, cancellationToken).ConfigureAwait(false);
            return Result.Ok<Unit, SeamError>(default);
        }
        catch (IOException exception)
        {
            return SeamErrors.IoFailure(SeamKind.Vfs, "writeBytes", exception.Message);
        }
        catch (OperationCanceledException)
        {
            return SeamErrors.Cancelled(SeamKind.Vfs, "writeBytes");
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> WriteText(
        string path,
        string content,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(content);
        return WriteBytes(path, Encoding.UTF8.GetBytes(content), options, cancellationToken);
    }

    /// <inheritdoc />
    public Task<Result<IReadOnlyList<VfsEntry>, SeamError>> List(
        string path,
        VfsListOptions options = default,
        CancellationToken cancellationToken = default)
    {
        var guarded = Guarded<string>(path, "list", cancellationToken, full => full);
        if (guarded.IsFailure(out var error))
        {
            return Task.FromResult(Result.Err<IReadOnlyList<VfsEntry>, SeamError>(error));
        }

        var full = guarded.Get();
        if (File.Exists(full))
        {
            return Task.FromResult(Result.Err<IReadOnlyList<VfsEntry>, SeamError>(SeamErrors.NotADirectory(full)));
        }

        if (!Directory.Exists(full))
        {
            return Task.FromResult(Result.Err<IReadOnlyList<VfsEntry>, SeamError>(SeamErrors.NotFound(full)));
        }

        var search = options.Recursive ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
        try
        {
            IReadOnlyList<VfsEntry> entries =
            [
                .. Directory.EnumerateDirectories(full, "*", search).Select(DirectoryEntryOf)
                    .Concat(Directory.EnumerateFiles(full, "*", search).Select(FileEntryOf))
                    .OrderBy(entry => entry.Path, StringComparer.Ordinal),
            ];
            return Task.FromResult(Result.Ok<IReadOnlyList<VfsEntry>, SeamError>(entries));
        }
        catch (IOException exception)
        {
            return Task.FromResult(Result.Err<IReadOnlyList<VfsEntry>, SeamError>(
                SeamErrors.IoFailure(SeamKind.Vfs, "list", exception.Message)));
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default)
    {
        var guarded = Guarded<string>(path, "createDirectory", cancellationToken, full => full);
        if (guarded.IsFailure(out var error)) return Task.FromResult(Result.Err<Unit, SeamError>(error));
        var full = guarded.Get();
        if (Directory.Exists(full) || File.Exists(full))
        {
            return Task.FromResult(options.Recursive
                ? Result.Ok<Unit, SeamError>(default)
                : Result.Err<Unit, SeamError>(SeamErrors.AlreadyExists(full)));
        }

        var parent = Path.GetDirectoryName(full);
        if (!options.Recursive && !string.IsNullOrEmpty(parent) && !Directory.Exists(parent))
        {
            return Task.FromResult(Result.Err<Unit, SeamError>(SeamErrors.NotFound(Normalize(parent))));
        }

        try
        {
            Directory.CreateDirectory(full);
            return Task.FromResult(Result.Ok<Unit, SeamError>(default));
        }
        catch (IOException exception)
        {
            return Task.FromResult(Result.Err<Unit, SeamError>(
                SeamErrors.IoFailure(SeamKind.Vfs, "createDirectory", exception.Message)));
        }
    }

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default)
    {
        var guarded = Guarded<string>(path, "delete", cancellationToken, full => full);
        if (guarded.IsFailure(out var error)) return Task.FromResult(Result.Err<Unit, SeamError>(error));
        var full = guarded.Get();
        try
        {
            if (File.Exists(full))
            {
                File.Delete(full);
                return Task.FromResult(Result.Ok<Unit, SeamError>(default));
            }

            if (!Directory.Exists(full))
            {
                return Task.FromResult(Result.Err<Unit, SeamError>(SeamErrors.NotFound(full)));
            }

            if (!options.Recursive && Directory.EnumerateFileSystemEntries(full).Any())
            {
                return Task.FromResult(Result.Err<Unit, SeamError>(SeamErrors.DirectoryNotEmpty(full)));
            }

            Directory.Delete(full, options.Recursive);
            return Task.FromResult(Result.Ok<Unit, SeamError>(default));
        }
        catch (IOException exception)
        {
            return Task.FromResult(Result.Err<Unit, SeamError>(
                SeamErrors.IoFailure(SeamKind.Vfs, "delete", exception.Message)));
        }
    }

    private static VfsEntry DirectoryEntryOf(string path) =>
        new(Normalize(path), VfsEntryType.Directory, 0, Directory.GetLastWriteTimeUtc(path));

    private static VfsEntry FileEntryOf(string path)
    {
        var info = new FileInfo(path);
        return new VfsEntry(
            Normalize(path),
            info.LinkTarget is null ? VfsEntryType.File : VfsEntryType.Link,
            info.Length,
            info.LastWriteTimeUtc);
    }

    private static string Normalize(string path) => path.Replace('\\', '/');

    private static Result<T, SeamError> Guarded<T>(
        string path,
        string operation,
        CancellationToken cancellationToken,
        Func<string, T> body)
    {
        if (cancellationToken.IsCancellationRequested) return SeamErrors.Cancelled(SeamKind.Vfs, operation);
        if (string.IsNullOrWhiteSpace(path))
        {
            return SeamErrors.InvalidArgument(SeamKind.Vfs, nameof(path), "The path must not be blank.");
        }

        try
        {
            return Result.Ok<T, SeamError>(body(Path.GetFullPath(path)));
        }
        catch (IOException exception)
        {
            return SeamErrors.IoFailure(SeamKind.Vfs, operation, exception.Message);
        }
    }
}
