namespace AtomiCloud.Diene.Interfaces.UnitTest.Meta;

/// <summary>Every operation fails, so no contract case can pass.</summary>
internal sealed class AlwaysFailingVfs : IVfs
{
    private static SeamError Error => SeamErrors.IoFailure(SeamKind.Vfs, "sabotage", "always fails");

    public Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<bool, SeamError>(Error));

    public Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(
        string path,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<ReadOnlyMemory<byte>, SeamError>(Error));

    public Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<string, SeamError>(Error));

    public Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<Unit, SeamError>(Error));

    public Task<Result<Unit, SeamError>> WriteText(
        string path,
        string content,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<Unit, SeamError>(Error));

    public Task<Result<IReadOnlyList<VfsEntry>, SeamError>> List(
        string path,
        VfsListOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<IReadOnlyList<VfsEntry>, SeamError>(Error));

    public Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<Unit, SeamError>(Error));

    public Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Err<Unit, SeamError>(Error));
}

/// <summary>Every operation succeeds vacuously, so failure cases cannot pass.</summary>
internal sealed class AlwaysSucceedingVfs : IVfs
{
    public Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<bool, SeamError>(true));

    public Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(
        string path,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<ReadOnlyMemory<byte>, SeamError>(ReadOnlyMemory<byte>.Empty));

    public Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<string, SeamError>(string.Empty));

    public Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<Unit, SeamError>(default));

    public Task<Result<Unit, SeamError>> WriteText(
        string path,
        string content,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<Unit, SeamError>(default));

    public Task<Result<IReadOnlyList<VfsEntry>, SeamError>> List(
        string path,
        VfsListOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<IReadOnlyList<VfsEntry>, SeamError>([]));

    public Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<Unit, SeamError>(default));

    public Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        Task.FromResult(Result.Ok<Unit, SeamError>(default));
}

/// <summary>Throws instead of returning a Result, which S33 forbids.</summary>
internal sealed class ThrowingVfs : IVfs
{
    public Task<Result<bool, SeamError>> Exists(string path, CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<ReadOnlyMemory<byte>, SeamError>> ReadBytes(
        string path,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<string, SeamError>> ReadText(string path, CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<Unit, SeamError>> WriteBytes(
        string path,
        ReadOnlyMemory<byte> bytes,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<Unit, SeamError>> WriteText(
        string path,
        string content,
        VfsWriteOptions options = default,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<IReadOnlyList<VfsEntry>, SeamError>> List(
        string path,
        VfsListOptions options = default,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<Unit, SeamError>> CreateDirectory(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");

    public Task<Result<Unit, SeamError>> Delete(
        string path,
        VfsDirectoryOptions options = default,
        CancellationToken cancellationToken = default) =>
        throw new InvalidOperationException("sabotage");
}
