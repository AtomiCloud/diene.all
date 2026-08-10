using System.Text;
using AtomiCloud.Diene.StandardConfig.Storage;
using FluentAssertions;

namespace AtomiCloud.Diene.StandardConfig.TestHelper.Storage;

/// <summary>
/// The ONE behavioural suite every <see cref="IBlockStorage" /> must satisfy.
/// </summary>
/// <remarks>
/// Contract parity lives or dies on there being a single suite: the meta tier runs this
/// against the real S3 implementation over a MinIO container AND against
/// <see cref="InMemoryBlockStorage" />, so a consumer that unit-tests with the fake is
/// testing against behaviour the real adapter is held to. Consumers who write their own
/// <see cref="IBlockStorage" /> can run it too — that is why it ships.
/// </remarks>
public static class BlockStorageContract
{
    /// <summary>Runs the whole contract against <paramref name="storage" />.</summary>
    public static async Task VerifyAsync(IBlockStorage storage, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(storage);

        await SaveReturnsTheKeyAndItsLink(storage, cancellationToken).ConfigureAwait(false);
        await SaveIsIdempotentOnTheSameKey(storage, cancellationToken).ConfigureAwait(false);
        LinksArePureAndStable(storage);
        NestedKeysKeepTheirSeparators(storage);
        SignedUrlsCarryTheKeyAndDifferFromThePlainLink(storage);
        EmptyKeysAreRejected(storage);
    }

    private static async Task SaveReturnsTheKeyAndItsLink(IBlockStorage storage, CancellationToken cancellationToken)
    {
        const string key = "contract/save-returns-handle.txt";
        var result = await storage
            .SaveAsync(Input(key, "save-returns-handle"), cancellationToken)
            .ConfigureAwait(false);

        result.IsSuccess(out var stored).Should().BeTrue("saving a small object to a reachable endpoint succeeds");
        stored!.Key.Should().Be(key);
        stored.Link.Should().Be(storage.GetLink(key), "the returned link is the public link for that key");
    }

    private static async Task SaveIsIdempotentOnTheSameKey(IBlockStorage storage, CancellationToken cancellationToken)
    {
        const string key = "contract/idempotent.txt";

        var first = await storage.SaveAsync(Input(key, "one"), cancellationToken).ConfigureAwait(false);
        var second = await storage.SaveAsync(Input(key, "two"), cancellationToken).ConfigureAwait(false);

        first.IsSuccess(out var a).Should().BeTrue();
        second.IsSuccess(out var b).Should().BeTrue("re-saving the same key overwrites rather than conflicting");
        b!.Link.Should().Be(a!.Link);
    }

    private static void LinksArePureAndStable(IBlockStorage storage)
    {
        const string key = "contract/stable.txt";
        storage.GetLink(key).Should().Be(storage.GetLink(key), "GetLink does no IO and never varies");
        storage.GetLink(key).Should().Contain("stable.txt");
    }

    private static void NestedKeysKeepTheirSeparators(IBlockStorage storage)
    {
        var link = storage.GetLink("a/b c/d.txt");
        link.Should().Contain("a/b%20c/d.txt", "path separators survive, the segments around them are encoded");
    }

    private static void SignedUrlsCarryTheKeyAndDifferFromThePlainLink(IBlockStorage storage)
    {
        const string key = "contract/signed.txt";
        var signed = storage.GetSignedUrl(key, new SignedUrlOptions { ExpiresIn = TimeSpan.FromMinutes(5) });

        signed.Should().Contain("signed.txt");
        signed.Should().NotBe(storage.GetLink(key), "a signed URL carries signature material the plain link does not");
        signed.Should().Contain("?", "the signature travels as query parameters");
    }

    private static void EmptyKeysAreRejected(IBlockStorage storage)
    {
        var link = () => storage.GetLink("  ");
        link.Should().Throw<ArgumentException>("a blank key is a caller bug, not a storable object");
    }

    private static SaveInput Input(string key, string body) => new()
    {
        Key = key,
        Body = Encoding.UTF8.GetBytes(body),
        ContentType = "text/plain",
    };
}
