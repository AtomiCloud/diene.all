using System.Text;
using AtomiCloud.Diene.StandardConfig.Storage;
using AtomiCloud.Diene.StandardConfig.TestHelper.Storage;

namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>Fixture invariants for the fake consumers unit-test against.</summary>
public class InMemoryBlockStorageTests
{
    private static SaveInput Input(string key = "a/b.txt", string body = "payload") => new()
    {
        Key = key,
        Body = Encoding.UTF8.GetBytes(body),
        ContentType = "text/plain",
    };

    [Fact]
    public async Task It_should_retain_what_it_was_given()
    {
        var storage = new InMemoryBlockStorage();

        await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        storage.Has("a/b.txt").Should().BeTrue();
        storage.Count.Should().Be(1);
        storage.Read("a/b.txt").IsSome(out var blob).Should().BeTrue();
        Encoding.UTF8.GetString(blob!.Body.Span).Should().Be("payload");
        blob.ContentType.Should().Be("text/plain");
    }

    [Fact]
    public async Task It_should_report_the_link_it_will_serve()
    {
        var storage = new InMemoryBlockStorage();

        var saved = await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        saved.IsSuccess(out var stored).Should().BeTrue();
        stored!.Link.Should().Be(storage.GetLink("a/b.txt"));
    }

    [Fact]
    public void It_should_report_none_for_an_object_that_was_never_saved() =>
        new InMemoryBlockStorage().Read("missing").IsNone().Should().BeTrue();

    [Fact]
    public void It_should_report_absence_without_reading() =>
        new InMemoryBlockStorage().Has("missing").Should().BeFalse();

    [Fact]
    public async Task It_should_clear_every_object()
    {
        var storage = new InMemoryBlockStorage();
        await storage.SaveAsync(Input(), TestContext.Current.CancellationToken);

        storage.Clear();

        storage.Count.Should().Be(0);
    }

    [Fact]
    public void It_should_honour_a_custom_link_root() =>
        new InMemoryBlockStorage("https://cdn.test/root/")
            .GetLink("a.txt")
            .Should()
            .Be("https://cdn.test/root/a.txt");

    [Fact]
    public void It_should_reject_a_blank_link_root()
    {
        var construct = () => new InMemoryBlockStorage("  ");
        construct.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_encode_key_segments_without_touching_separators() =>
        new InMemoryBlockStorage().GetLink("a b/c.txt").Should().Be("memory://block-storage/a%20b/c.txt");

    [Fact]
    public void It_should_carry_the_method_and_expiry_into_a_signed_url()
    {
        var signed = new InMemoryBlockStorage().GetSignedUrl(
            "a.txt",
            new SignedUrlOptions { ExpiresIn = TimeSpan.FromMinutes(1), Method = SignedUrlMethod.Put });

        signed.Should().Contain("X-Method=PUT").And.Contain("X-Expires=60");
    }

    [Fact]
    public void It_should_default_a_signed_url_to_a_fifteen_minute_get() =>
        new InMemoryBlockStorage()
            .GetSignedUrl("a.txt")
            .Should()
            .Contain("X-Method=GET")
            .And.Contain("X-Expires=900");

    [Fact]
    public void It_should_reject_a_blank_key_when_signing()
    {
        var sign = () => new InMemoryBlockStorage().GetSignedUrl("");
        sign.Should().Throw<ArgumentException>();
    }

    [Fact]
    public async Task It_should_reject_a_null_upload()
    {
        var save = async () => await new InMemoryBlockStorage()
            .SaveAsync(null!, TestContext.Current.CancellationToken);

        await save.Should().ThrowAsync<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_observe_cancellation()
    {
        using var cancelled = new CancellationTokenSource();
        await cancelled.CancelAsync();

        var save = async () => await new InMemoryBlockStorage().SaveAsync(Input(), cancelled.Token);

        await save.Should().ThrowAsync<OperationCanceledException>();
    }
}
