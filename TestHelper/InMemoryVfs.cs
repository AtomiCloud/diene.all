using System.Text;

namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>
/// A deterministic in-memory <see cref="IVfs"/>. It satisfies the same seam
/// contract as a host-backed filesystem — see <see cref="SeamContracts.Vfs"/> —
/// so consumers can swap it in without changing behavioural expectations.
/// </summary>
/// <param name="modifiedAt">The modification time every entry reports.</param>
public sealed class InMemoryVfs(DateTimeOffset? modifiedAt = null) : IVfs
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, byte[]> _files = new(StringComparer.Ordinal);
    private readonly HashSet<string> _directories = new(StringComparer.Ordinal) { VfsPath.Root };
    private readonly Queue<SeamError> _failures = new();

    private readonly DateTimeOffset _modifiedAt =
        (modifiedAt ?? new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero)).ToUniversalTime();

    /// <summary>A snapshot of the stored files, keyed by normalized path.</summary>
    public IReadOnlyDictionary<string, ReadOnlyMemory<byte>> Files
    {
        get
        {
            lock (_gate)
            {
                return _files.ToDictionary(
                    entry => entry.Key,
                    entry => new ReadOnlyMemory<byte>(entry.Value),
                    StringComparer.Ordinal);
            }
        }
    }

    /// <summary>A snapshot of the stored directories, in path order.</summary>
    public IReadOnlyList<string> Directories
    {
        get
        {
            lock (_gate) return [.. _directories.Order(StringComparer.Ordinal)];
        }
    }

    /// <summary>Queues one failure to be returned by the next seam call.</summary>
    public void EnqueueFailure(SeamError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        lock (_gate) _failures.Enqueue(error);
    }

    /// <summary>Seeds a file and every directory above it.</summary>
    public void Seed(string path, string content)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        ArgumentNullException.ThrowIfNull(content);
        var normalized = VfsPath.Normalize(path);
        lock (_gate)
        {
            EnsureParents(normalized);
            _files[normalized] = Encoding.UTF8.GetBytes(content);
        }
    }

    /// <inheritdoc />
    public Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<bool>(path, normalized =>
            _files.ContainsKey(normalized) || _directories.Contains(normalized)));

    /// <inheritdoc />
    public Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(
        string path,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<ReadOnlyMemory<byte>>(path, normalized =>
            _files.TryGetValue(normalized, out var bytes)
                ? Result.Ok<ReadOnlyMemory<byte>, SeamError>(bytes.ToArray())
                : SeamErrors.NotFound(normalized)));

    /// <inheritdoc />
    public async Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default)
    {
        var bytes = await ReadBytes(path, cancellationToken).ConfigureAwait(false);
        return bytes.Map(value => Encoding.UTF8.GetString(value.Span));
    }

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<Unit>(path, normalized =>
        {
            var parent = VfsPath.Parent(normalized).GetOr(VfsPath.Root);
            if (!_directories.Contains(parent))
            {
                if (!options.CreateParents) return SeamErrors.NotFound(parent);
                EnsureParents(normalized);
            }

            _files[normalized] = bytes.ToArray();
            return Result.Ok<Unit, SeamError>(default);
        }));

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
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<IReadOnlyList<VfsEntry>>(path, normalized =>
        {
            if (_files.ContainsKey(normalized)) return SeamErrors.NotADirectory(normalized);
            if (!_directories.Contains(normalized)) return SeamErrors.NotFound(normalized);

            bool Selected(string candidate) => options.Recursive
                ? VfsPath.IsBelow(candidate, normalized)
                : VfsPath.IsDirectChild(candidate, normalized);

            IReadOnlyList<VfsEntry> entries =
            [
                .. _directories
                    .Where(Selected)
                    .Select(directory => new VfsEntry(directory, VfsEntryType.Directory, 0, _modifiedAt))
                    .Concat(_files
                        .Where(file => Selected(file.Key))
                        .Select(file => new VfsEntry(file.Key, VfsEntryType.File, file.Value.Length, _modifiedAt)))
                    .OrderBy(entry => entry.Path, StringComparer.Ordinal),
            ];
            return Result.Ok<IReadOnlyList<VfsEntry>, SeamError>(entries);
        }));

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<Unit>(path, normalized =>
        {
            if (_directories.Contains(normalized) || _files.ContainsKey(normalized))
            {
                return options.Recursive
                    ? Result.Ok<Unit, SeamError>(default)
                    : Result.Err<Unit, SeamError>(SeamErrors.AlreadyExists(normalized));
            }

            var parent = VfsPath.Parent(normalized).GetOr(VfsPath.Root);
            if (!_directories.Contains(parent) && !options.Recursive) return SeamErrors.NotFound(parent);
            EnsureParents(normalized);
            _directories.Add(normalized);
            return Result.Ok<Unit, SeamError>(default);
        }));

    /// <inheritdoc />
    public Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Locked<Unit>(path, normalized =>
        {
            if (_files.Remove(normalized)) return Result.Ok<Unit, SeamError>(default);
            if (!_directories.Contains(normalized)) return SeamErrors.NotFound(normalized);

            List<string> children =
            [
                .. _files.Keys
                    .Concat(_directories)
                    .Where(candidate => VfsPath.IsBelow(candidate, normalized)),
            ];
            if (children.Count > 0 && !options.Recursive) return SeamErrors.DirectoryNotEmpty(normalized);

            foreach (var child in children)
            {
                _files.Remove(child);
                _directories.Remove(child);
            }

            _directories.Remove(normalized);
            return Result.Ok<Unit, SeamError>(default);
        }));

    private Result<T, SeamError> Locked<T>(string path, Func<string, Result<T, SeamError>> body)
    {
        lock (_gate)
        {
            if (_failures.TryDequeue(out var failure)) return failure;
            return string.IsNullOrWhiteSpace(path)
                ? SeamErrors.InvalidArgument(SeamKind.Vfs, nameof(path), "The path must not be blank.")
                : body(VfsPath.Normalize(path));
        }
    }

    private void EnsureParents(string normalized)
    {
        var parent = VfsPath.Parent(normalized);
        while (parent.IsSome(out var value))
        {
            _directories.Add(value);
            parent = VfsPath.Parent(value);
        }
    }
}
