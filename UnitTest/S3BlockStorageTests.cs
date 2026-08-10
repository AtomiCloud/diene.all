using System.Text;
using Amazon.Runtime;
using Amazon.S3;
using AtomiCloud.Diene.StandardConfig.Storage;

namespace AtomiCloud.DotnetBase.UnitTest;

public class S3BlockStorageTests
{
    private static StorageOption Entry(bool forcePathStyle = true, string endpoint = "http://localhost:9000") => new()
    {
        Endpoint = endpoint,
        Region = "us-east-1",
        Bucket = "app",
        AccessKeyId = "key",
        SecretAccessKey = "secret",
        ForcePathStyle = forcePathStyle,
    };

    private static SaveInput Input(string key = "demo/object.txt") => new()
    {
        Key = key,
        Body = Encoding.UTF8.GetBytes("payload"),
        ContentType = "text/plain",
    };

    // ── client configuration ────────────────────────────────────────────────────────────

    [Fact]
    public void It_should_configure_the_client_from_the_connection_block()
    {
        var config = S3BlockStorage.ClientConfig(Entry());

        // The SDK normalizes a service URL with a trailing slash.
        config.ServiceURL.Should().Be("http://localhost:9000/");
        config.AuthenticationRegion.Should().Be("us-east-1");
        config.ForcePathStyle.Should().BeTrue();
    }

    [Fact]
    public void It_should_leave_path_style_off_for_virtual_hosted_providers() =>
        S3BlockStorage.ClientConfig(Entry(forcePathStyle: false)).ForcePathStyle.Should().BeFalse();

    [Fact]
    public void It_should_reject_a_null_entry_when_configuring()
    {
        var config = () => S3BlockStorage.ClientConfig(null!);
        config.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_build_a_production_instance_that_owns_its_client()
    {
        using var storage = S3BlockStorage.Create(Entry());

        storage.GetLink("a.txt").Should().Be("http://localhost:9000/app/a.txt");
    }

    [Fact]
    public void It_should_reject_a_null_entry_when_creating()
    {
        var create = () => S3BlockStorage.Create(null!);
        create.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_client()
    {
        var construct = () => new S3BlockStorage(null!, Entry());
        construct.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_entry_when_wrapping_a_client()
    {
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(Entry()));
        var construct = () => new S3BlockStorage(client, null!);
        construct.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_leave_a_borrowed_client_open_when_disposed()
    {
        var entry = Entry();
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(entry));

        new S3BlockStorage(client, entry).Dispose();

        // Still usable, because the caller owns it.
        client.Config.ServiceURL.Should().StartWith(entry.Endpoint);
    }

    // ── links ───────────────────────────────────────────────────────────────────────────

    [Fact]
    public void It_should_build_a_path_style_link()
    {
        using var storage = Storage(Entry());

        storage.GetLink("nested/key.txt").Should().Be("http://localhost:9000/app/nested/key.txt");
    }

    [Fact]
    public void It_should_build_a_virtual_hosted_link()
    {
        using var storage = Storage(Entry(forcePathStyle: false, endpoint: "https://fly.storage.tigris.dev"));

        storage.GetLink("nested/key.txt").Should().Be("https://app.fly.storage.tigris.dev/nested/key.txt");
    }

    [Fact]
    public void It_should_keep_a_virtual_hosted_endpoint_path_prefix()
    {
        using var storage = Storage(Entry(forcePathStyle: false, endpoint: "https://edge.example.com/s3/"));

        storage.GetLink("key.txt").Should().Be("https://app.edge.example.com/s3/key.txt");
    }

    [Fact]
    public void It_should_fall_back_to_path_style_for_an_unparseable_endpoint()
    {
        // The AWS client refuses a non-URL ServiceURL outright, so this branch is only
        // reachable through a hand-wired client — but a link builder that throws deep inside
        // UriBuilder would be a worse failure than a degraded link.
        var entry = Entry(forcePathStyle: false, endpoint: "not-a-url");
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(Entry()));
        using var storage = new S3BlockStorage(client, entry);

        storage.GetLink("key.txt").Should().Be("not-a-url/app/key.txt");
    }

    [Fact]
    public void It_should_encode_segments_but_not_separators()
    {
        using var storage = Storage(Entry());

        storage.GetLink("a b/c&d.txt").Should().Be("http://localhost:9000/app/a%20b/c%26d.txt");
    }

    [Fact]
    public void It_should_reject_a_blank_key_for_a_link()
    {
        using var storage = Storage(Entry());

        var link = () => storage.GetLink("  ");
        link.Should().Throw<ArgumentException>();
    }

    // ── signed urls ─────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData(SignedUrlMethod.Get)]
    [InlineData(SignedUrlMethod.Put)]
    [InlineData(SignedUrlMethod.Delete)]
    [InlineData(SignedUrlMethod.Head)]
    public void It_should_sign_a_url_for_every_supported_method(SignedUrlMethod method)
    {
        using var storage = Storage(Entry());

        var signed = storage.GetSignedUrl("key.txt", new SignedUrlOptions { Method = method });

        signed.Should().Contain("key.txt").And.Contain("X-Amz-Signature");
    }

    [Fact]
    public void It_should_default_to_a_fifteen_minute_get()
    {
        using var storage = Storage(Entry());

        SignedUrlOptions.DefaultExpiry.Should().Be(TimeSpan.FromMinutes(15));
        SignedExpiry(storage.GetSignedUrl("key.txt")).Should().BeInRange(898, 900);
    }

    [Fact]
    public void It_should_honour_an_explicit_expiry()
    {
        using var storage = Storage(Entry());

        var signed = storage.GetSignedUrl("key.txt", new SignedUrlOptions { ExpiresIn = TimeSpan.FromMinutes(5) });

        // The SDK derives X-Amz-Expires from the wall clock between signing and expiry, so a
        // tick landing mid-call legitimately yields 299 rather than 300.
        SignedExpiry(signed).Should().BeInRange(298, 300);
    }

    /// <summary>The X-Amz-Expires value the signer put on a presigned URL.</summary>
    private static int SignedExpiry(string signedUrl)
    {
        var match = System.Text.RegularExpressions.Regex.Match(signedUrl, "X-Amz-Expires=([0-9]+)");
        match.Success.Should().BeTrue(signedUrl);
        return int.Parse(match.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
    }

    [Fact]
    public void It_should_reject_a_blank_key_when_signing()
    {
        using var storage = Storage(Entry());

        var sign = () => storage.GetSignedUrl("");
        sign.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_an_unsupported_signed_url_method()
    {
        using var storage = Storage(Entry());

        var sign = () => storage.GetSignedUrl("key.txt", new SignedUrlOptions { Method = (SignedUrlMethod)99 });
        sign.Should().Throw<StandardConfigException>().WithMessage("*99*");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void It_should_refuse_to_sign_a_url_that_is_already_expired(int minutes)
    {
        // The SDK signs it happily and the link then fails only at use, which is a much
        // worse place to find out.
        using var storage = Storage(Entry());

        var sign = () => storage.GetSignedUrl(
            "key.txt",
            new SignedUrlOptions { ExpiresIn = TimeSpan.FromMinutes(minutes) });

        sign.Should().Throw<ArgumentOutOfRangeException>();
    }

    // ── uploads ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public async Task It_should_upload_an_object_and_return_its_handle()
    {
        var entry = Entry();
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(entry));
        using var storage = new S3BlockStorage(client, entry);

        var result = await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        result.IsSuccess(out var stored).Should().BeTrue();
        stored!.Key.Should().Be("demo/object.txt");
        stored.Link.Should().Be("http://localhost:9000/app/demo/object.txt");

        client.Puts.Should().ContainSingle();
        client.Puts[0].BucketName.Should().Be("app");
        client.Puts[0].ContentType.Should().Be("text/plain");
    }

    [Fact]
    public async Task It_should_upload_without_a_content_type()
    {
        var entry = Entry();
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(entry));
        using var storage = new S3BlockStorage(client, entry);

        var result = await storage.SaveAsync(new SaveInput { Key = "k.bin", Body = new byte[] { 1, 2, 3 } }, TestContext.Current.CancellationToken);

        result.IsSuccess().Should().BeTrue();
        client.Puts[0].ContentType.Should().BeNull();
    }

    [Fact]
    public async Task It_should_return_an_error_when_the_transport_fails()
    {
        var entry = Entry();
        using var client = new StubAmazonS3(
            S3BlockStorage.ClientConfig(entry),
            new AmazonS3Exception("bucket is on fire"));
        using var storage = new S3BlockStorage(client, entry);

        var result = await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        result.IsFailure(out var error).Should().BeTrue();
        error!.Message.Should().Contain("demo/object.txt");
        error.Cause.Should().BeOfType<AmazonS3Exception>();
        error.ToString().Should().Contain("bucket is on fire");
    }

    [Fact]
    public async Task It_should_return_an_error_when_the_client_faults_locally()
    {
        var entry = Entry();
        using var client = new StubAmazonS3(
            S3BlockStorage.ClientConfig(entry),
            new AmazonClientException("no route"));
        using var storage = new S3BlockStorage(client, entry);

        (await storage.SaveAsync(Input(), TestContext.Current.CancellationToken)).IsFailure().Should().BeTrue();
    }

    [Fact]
    public async Task It_should_let_an_unexpected_exception_escape()
    {
        // Only transport faults are railway-oriented; a programming error must not be
        // laundered into an Err the caller treats as a retryable upload failure.
        var entry = Entry();
        using var client = new StubAmazonS3(S3BlockStorage.ClientConfig(entry), new InvalidOperationException("bug"));
        using var storage = new S3BlockStorage(client, entry);

        var save = async () => await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        await save.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task It_should_reject_a_null_upload()
    {
        using var storage = Storage(Entry());

        var save = async () => await storage.SaveAsync(null!, TestContext.Current.CancellationToken);
        await save.Should().ThrowAsync<ArgumentNullException>();
    }

    // ── the error type ──────────────────────────────────────────────────────────────────

    [Fact]
    public void It_should_render_a_causeless_error_as_its_message() =>
        new StorageError("plain").ToString().Should().Be("plain");

    private static S3BlockStorage Storage(StorageOption entry) =>
        new(new StubAmazonS3(S3BlockStorage.ClientConfig(entry)), entry);
}
