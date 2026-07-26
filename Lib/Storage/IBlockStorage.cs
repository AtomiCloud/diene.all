namespace AtomiCloud.Diene.StandardConfig.Storage;

/// <summary>A failure from a block-storage IO operation.</summary>
public sealed class StorageError(string message, Exception? cause = null)
{
    /// <summary>What went wrong.</summary>
    public string Message { get; } = message;

    /// <summary>The underlying cause, when one was thrown.</summary>
    public Exception? Cause { get; } = cause;

    /// <inheritdoc />
    public override string ToString() => Cause is null ? Message : $"{Message}: {Cause.Message}";
}

/// <summary>An object to upload through <see cref="IBlockStorage.SaveAsync" />.</summary>
public sealed class SaveInput
{
    /// <summary>Object key (path within the bucket).</summary>
    public required string Key { get; init; }

    /// <summary>Object bytes.</summary>
    public required ReadOnlyMemory<byte> Body { get; init; }

    /// <summary>Optional MIME type stored with the object.</summary>
    public string? ContentType { get; init; }
}

/// <summary>A stored object handle returned by <see cref="IBlockStorage.SaveAsync" />.</summary>
public sealed class StoredObject
{
    /// <summary>The object key it was stored under.</summary>
    public required string Key { get; init; }

    /// <summary>The public (unsigned) link to the object.</summary>
    public required string Link { get; init; }
}

/// <summary>Options for <see cref="IBlockStorage.GetSignedUrl" />.</summary>
public sealed class SignedUrlOptions
{
    /// <summary>The default signed-URL lifetime: fifteen minutes.</summary>
    public static readonly TimeSpan DefaultExpiry = TimeSpan.FromMinutes(15);

    /// <summary>How long the signature stays valid.</summary>
    public TimeSpan ExpiresIn { get; init; } = DefaultExpiry;

    /// <summary>The HTTP method the signature authorizes.</summary>
    public SignedUrlMethod Method { get; init; } = SignedUrlMethod.Get;
}

/// <summary>The HTTP methods a signed URL may authorize.</summary>
public enum SignedUrlMethod
{
    /// <summary>Read the object.</summary>
    Get,

    /// <summary>Write the object.</summary>
    Put,

    /// <summary>Delete the object.</summary>
    Delete,

    /// <summary>Read the object's metadata only.</summary>
    Head,
}

/// <summary>
/// The block-storage surface: upload an object, get a public link, get a signed URL. That is
/// the WHOLE interface.
/// </summary>
/// <remarks>
/// Deliberately tiny. It ships here — beside the <c>storage</c> preset that configures it —
/// with exactly one S3-compatible implementation, and both are proven by this library's own
/// suites, so consumers never integration-test object storage themselves. Anything richer
/// (lifecycle rules, multipart, listing) belongs in the consumer that actually needs it.
/// </remarks>
public interface IBlockStorage
{
    /// <summary>
    /// Uploads an object. Network IO, so it is railway-oriented: a transport failure returns
    /// <c>Err&lt;StorageError&gt;</c> rather than throwing.
    /// </summary>
    Task<Result<StoredObject, StorageError>> SaveAsync(SaveInput input, CancellationToken cancellationToken = default);

    /// <summary>The public, unsigned link for an object key. Pure — no IO.</summary>
    string GetLink(string key);

    /// <summary>
    /// A time-limited signed URL for an object key. Deterministic given the connection block
    /// and the clock; no IO.
    /// </summary>
    string GetSignedUrl(string key, SignedUrlOptions? options = null);
}
