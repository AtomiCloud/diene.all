using AtomiCloud.Diene.StandardConfig.Storage;
using AtomiCloud.Diene.StandardConfig.TestHelper.Containers;
using AtomiCloud.Diene.StandardConfig.TestHelper.Storage;

namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// Contract parity: ONE behavioural suite, run against the real S3 adapter over a MinIO
/// container AND against the in-memory fake.
/// </summary>
/// <remarks>
/// This is what earns a consumer the right to unit-test against
/// <see cref="InMemoryBlockStorage" />. Without it the fake is a guess about S3's behaviour,
/// and every consumer suite built on it is green for a reason nobody has checked.
/// </remarks>
[Collection("containers")]
public class BlockStorageParityTests
{
    [Fact]
    public async Task The_fake_should_satisfy_the_block_storage_contract() =>
        await BlockStorageContract.VerifyAsync(new InMemoryBlockStorage(), TestContext.Current.CancellationToken);

    [Fact]
    public async Task The_real_s3_adapter_should_satisfy_the_same_contract()
    {
        var token = TestContext.Current.CancellationToken;

        await using var minio = await StandardConfigContainers.StartStorageAsync(cancellationToken: token);
        using var storage = S3BlockStorage.Create(minio.Entry);

        await BlockStorageContract.VerifyAsync(storage, token);
    }

    [Fact]
    public async Task The_contract_should_reject_an_implementation_that_breaks_it()
    {
        // Assert-the-asserter for the parity suite itself: a suite that passes everything is
        // not a contract, it is decoration.
        var verify = async () => await BlockStorageContract.VerifyAsync(
            new BrokenBlockStorage(),
            TestContext.Current.CancellationToken);

        await verify.Should().ThrowAsync<Exception>();
    }

    [Fact]
    public async Task The_contract_should_reject_a_null_subject()
    {
        var verify = async () => await BlockStorageContract.VerifyAsync(
            null!,
            TestContext.Current.CancellationToken);

        await verify.Should().ThrowAsync<ArgumentNullException>();
    }

    /// <summary>An implementation that returns a link unrelated to the key it stored.</summary>
    private sealed class BrokenBlockStorage : IBlockStorage
    {
        public Task<Result<StoredObject, StorageError>> SaveAsync(
            SaveInput input,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Result.Ok<StoredObject, StorageError>(new StoredObject
            {
                Key = input.Key,
                Link = "https://elsewhere.invalid/not-the-key",
            }));

        public string GetLink(string key) => $"https://elsewhere.invalid/{key}";

        public string GetSignedUrl(string key, SignedUrlOptions? options = null) => GetLink(key);
    }
}
