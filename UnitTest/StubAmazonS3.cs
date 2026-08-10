using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// The smallest S3 client that lets the adapter's whole code path run without a network.
/// </summary>
/// <remarks>
/// <see cref="IAmazonS3" /> is enormous and the adapter touches exactly two members of it, so
/// this derives from the real <see cref="AmazonS3Client" /> — inheriting a working presigner
/// and overriding only the one call that would otherwise reach the wire.
/// </remarks>
internal sealed class StubAmazonS3 : AmazonS3Client
{
    private readonly Exception? _failure;

    internal StubAmazonS3(AmazonS3Config config, Exception? failure = null)
        : base(new BasicAWSCredentials("key", "secret"), config) => _failure = failure;

    internal List<PutObjectRequest> Puts { get; } = [];

    public override Task<PutObjectResponse> PutObjectAsync(
        PutObjectRequest request,
        CancellationToken cancellationToken = default)
    {
        Puts.Add(request);
        return _failure is null
            ? Task.FromResult(new PutObjectResponse())
            : Task.FromException<PutObjectResponse>(_failure);
    }
}
