using System.Collections.Concurrent;
using System.Globalization;
using AtomiCloud.Diene.StandardConfig.Storage;

namespace AtomiCloud.Diene.StandardConfig.TestHelper.Storage;

/// <summary>A stored blob, exposed for assertions.</summary>
public sealed class StoredBlob
{
    /// <summary>The stored bytes.</summary>
    public required ReadOnlyMemory<byte> Body { get; init; }

    /// <summary>The MIME type it was stored with, when one was supplied.</summary>
    public string? ContentType { get; init; }
}

/// <summary>
/// An in-memory <see cref="IBlockStorage" /> for unit tiers: no container, no network, no
/// credentials.
/// </summary>
/// <remarks>
/// Consumers should reach for this whenever object storage is incidental to what they are
/// testing. It is not a guess at S3's behaviour — the meta tier runs ONE shared contract
/// suite (<see cref="BlockStorageContract" />) against both this fake and the real
/// <c>S3BlockStorage</c> over MinIO, so the two are proven to agree on the surface consumers
/// actually depend on.
/// </remarks>
public sealed class InMemoryBlockStorage : IBlockStorage
{
    private readonly ConcurrentDictionary<string, StoredBlob> _objects = new(StringComparer.Ordinal);
    private readonly string _baseUrl;

    /// <summary>Creates the fake, optionally overriding the deterministic link root.</summary>
    public InMemoryBlockStorage(string baseUrl = "memory://block-storage")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(baseUrl);
        _baseUrl = baseUrl.TrimEnd('/');
    }

    /// <inheritdoc />
    public Task<Result<StoredObject, StorageError>> SaveAsync(
        SaveInput input,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        cancellationToken.ThrowIfCancellationRequested();

        _objects[input.Key] = new StoredBlob { Body = input.Body, ContentType = input.ContentType };

        return Task.FromResult(Result.Ok<StoredObject, StorageError>(new StoredObject
        {
            Key = input.Key,
            Link = GetLink(input.Key),
        }));
    }

    /// <inheritdoc />
    public string GetLink(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        return $"{_baseUrl}/{EncodeKey(key)}";
    }

    /// <inheritdoc />
    public string GetSignedUrl(string key, SignedUrlOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        options ??= new SignedUrlOptions();

        var expires = ((int)options.ExpiresIn.TotalSeconds).ToString(CultureInfo.InvariantCulture);
        var method = options.Method.ToString().ToUpperInvariant();
        return $"{GetLink(key)}?X-Sig=memory&X-Method={method}&X-Expires={expires}";
    }

    /// <summary>Whether an object was saved under <paramref name="key" />.</summary>
    public bool Has(string key) => _objects.ContainsKey(key);

    /// <summary>The stored blob for <paramref name="key" />, or None.</summary>
    public Option<StoredBlob> Read(string key) =>
        _objects.TryGetValue(key, out var blob) ? Option.Some(blob) : Option.None<StoredBlob>();

    /// <summary>The number of stored objects.</summary>
    public int Count => _objects.Count;

    /// <summary>Drops every stored object.</summary>
    public void Clear() => _objects.Clear();

    private static string EncodeKey(string key) =>
        string.Join('/', key.Split('/').Select(Uri.EscapeDataString));
}
