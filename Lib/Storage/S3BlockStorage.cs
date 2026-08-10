using System.Globalization;
using Amazon;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using AtomiCloud.Diene.StandardConfig.Presets;

namespace AtomiCloud.Diene.StandardConfig.Storage;

/// <summary>
/// The one S3-compatible <see cref="IBlockStorage" /> implementation, configured entirely
/// from a <see cref="StorageOption" /> entry.
/// </summary>
/// <remarks>
/// The AWS client arrives through the constructor rather than being built inside, so the
/// whole adapter — including its failure path — is exercised by the unit tier against a
/// stub, and the int tier proves the same code against a real MinIO container. Use
/// <see cref="Create" /> to build the ordinary production instance.
/// </remarks>
public sealed class S3BlockStorage : IBlockStorage, IDisposable
{
    private readonly IAmazonS3 _client;
    private readonly StorageOption _entry;
    private readonly bool _ownsClient;

    /// <summary>Wraps an existing S3 client. The caller keeps ownership of it.</summary>
    public S3BlockStorage(IAmazonS3 client, StorageOption entry)
        : this(client, entry, ownsClient: false) { }

    private S3BlockStorage(IAmazonS3 client, StorageOption entry, bool ownsClient)
    {
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(entry);
        _client = client;
        _entry = entry;
        _ownsClient = ownsClient;
    }

    /// <summary>Builds the production instance: an S3 client wired from the connection block.</summary>
    public static S3BlockStorage Create(StorageOption entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        return new S3BlockStorage(new AmazonS3Client(Credentials(entry), ClientConfig(entry)), entry, ownsClient: true);
    }

    /// <summary>The S3 client configuration this preset entry describes.</summary>
    public static AmazonS3Config ClientConfig(StorageOption entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        return new AmazonS3Config
        {
            ServiceURL = entry.Endpoint,
            AuthenticationRegion = entry.Region,
            // A custom ServiceURL and a RegionEndpoint are mutually exclusive in the SDK, so
            // the region travels as the signing region only.
            ForcePathStyle = entry.ForcePathStyle,
        };
    }

    private static AWSCredentials Credentials(StorageOption entry) =>
        new BasicAWSCredentials(entry.AccessKeyId, entry.SecretAccessKey);

    /// <inheritdoc />
    public async Task<Result<StoredObject, StorageError>> SaveAsync(
        SaveInput input,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);

        try
        {
            using var body = new MemoryStream(input.Body.ToArray(), writable: false);
            var request = new PutObjectRequest
            {
                BucketName = _entry.Bucket,
                Key = input.Key,
                InputStream = body,
            };
            if (!string.IsNullOrWhiteSpace(input.ContentType)) request.ContentType = input.ContentType;

            await _client.PutObjectAsync(request, cancellationToken).ConfigureAwait(false);

            return Result.Ok<StoredObject, StorageError>(new StoredObject
            {
                Key = input.Key,
                Link = GetLink(input.Key),
            });
        }
        catch (Exception exception) when (exception is AmazonServiceException or AmazonClientException or IOException)
        {
            return Result.Err<StoredObject, StorageError>(
                new StorageError($"failed to upload object \"{input.Key}\"", exception));
        }
    }

    /// <inheritdoc />
    public string GetLink(string key)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        var root = _entry.Endpoint.TrimEnd('/');
        return _entry.ForcePathStyle
            ? $"{root}/{_entry.Bucket}/{EncodeKey(key)}"
            : InsertBucketIntoHost(root, _entry.Bucket, EncodeKey(key));
    }

    /// <inheritdoc />
    public string GetSignedUrl(string key, SignedUrlOptions? options = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        options ??= new SignedUrlOptions();

        // The SDK happily signs an already-expired URL, which is never what a caller meant
        // and produces a link that fails only at use. Refuse it here instead.
        if (options.ExpiresIn <= TimeSpan.Zero)
            throw new ArgumentOutOfRangeException(
                nameof(options),
                options.ExpiresIn,
                "a signed URL must expire in the future");

        return _client.GetPreSignedURL(new GetPreSignedUrlRequest
        {
            BucketName = _entry.Bucket,
            Key = key,
            Verb = Verb(options.Method),
            Expires = DateTime.UtcNow.Add(options.ExpiresIn),
        });
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (_ownsClient) _client.Dispose();
    }

    private static HttpVerb Verb(SignedUrlMethod method) => method switch
    {
        SignedUrlMethod.Get => HttpVerb.GET,
        SignedUrlMethod.Put => HttpVerb.PUT,
        SignedUrlMethod.Delete => HttpVerb.DELETE,
        SignedUrlMethod.Head => HttpVerb.HEAD,
        _ => throw new StandardConfigException(
            string.Create(CultureInfo.InvariantCulture, $"unsupported signed-URL method {method}")),
    };

    /// <summary>Percent-encodes each path segment without touching the <c>/</c> separators.</summary>
    private static string EncodeKey(string key) =>
        string.Join('/', key.Split('/').Select(Uri.EscapeDataString));

    /// <summary>
    /// Virtual-hosted style puts the bucket in the hostname
    /// (<c>https://bucket.host/key</c>), which is what Tigris and S3 proper expect.
    /// </summary>
    private static string InsertBucketIntoHost(string root, string bucket, string encodedKey)
    {
        if (!Uri.TryCreate(root, UriKind.Absolute, out var uri)) return $"{root}/{bucket}/{encodedKey}";

        var builder = new UriBuilder(uri) { Host = $"{bucket}.{uri.Host}" };
        var prefix = builder.Uri.GetLeftPart(UriPartial.Authority) + uri.AbsolutePath.TrimEnd('/');
        return $"{prefix}/{encodedKey}";
    }
}
