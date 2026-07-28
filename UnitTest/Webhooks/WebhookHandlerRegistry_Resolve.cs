using System.Text.Json.Nodes;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Webhooks;

public class WebhookHandlerRegistry_Resolve
{
    [Fact]
    public void It_should_resolve_a_registered_provider()
    {
        // Arrange
        var handler = new RecordingWebhookHandler("stripe");
        var subject = new WebhookHandlerRegistry([handler]);

        // Act
        var found = subject.TryResolve("stripe", out var actual);

        // Assert
        found.Should().BeTrue();
        actual.Should().BeSameAs(handler);
    }

    [Fact]
    public void It_should_resolve_a_provider_regardless_of_route_casing()
    {
        // Arrange — the body must carry a lowercase provider, but a route segment is a URL and
        // refusing it on casing alone would report a stale address that is not stale.
        var subject = new WebhookHandlerRegistry([new RecordingWebhookHandler("stripe")]);

        // Act
        var found = subject.TryResolve("STRIPE", out _);

        // Assert
        found.Should().BeTrue();
    }

    [Theory]
    [ClassData(typeof(UnknownProviderCases))]
    public void It_should_report_an_unknown_provider_as_absent_rather_than_failing(string? provider)
    {
        // Arrange
        var subject = new WebhookHandlerRegistry([new RecordingWebhookHandler("stripe")]);

        // Act
        var found = subject.TryResolve(provider!, out var actual);

        // Assert
        found.Should().BeFalse();
        actual.Should().BeNull();
    }

    [Fact]
    public void It_should_list_every_registered_provider()
    {
        // Arrange
        var subject = new WebhookHandlerRegistry(
            [new RecordingWebhookHandler("stripe"), new RecordingWebhookHandler("paypal")]);

        // Act
        var actual = subject.Providers;

        // Assert
        actual.Should().BeEquivalentTo(["stripe", "paypal"]);
    }

    [Fact]
    public void It_should_accept_an_empty_registration_set()
    {
        // Arrange — a service may enable the engine without subscribing to any provider.
        var subject = new WebhookHandlerRegistry([]);

        // Act
        var found = subject.TryResolve("stripe", out _);

        // Assert
        subject.Providers.Should().BeEmpty();
        found.Should().BeFalse();
    }

    [Fact]
    public void It_should_refuse_two_handlers_for_one_provider_at_composition()
    {
        // Arrange — whichever the container enumerated first would silently win, so half the
        // events would be processed by the wrong code with nothing reporting it.
        var handlers = new List<IWebhookHandler>
        {
            new RecordingWebhookHandler("stripe"),
            new RecordingWebhookHandler("stripe"),
        };

        // Act
        var act = () => new WebhookHandlerRegistry(handlers);

        // Assert
        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*'stripe' has more than one handler*");
    }

    [Fact]
    public void It_should_refuse_two_handlers_whose_providers_differ_only_by_case()
    {
        // Arrange
        var handlers = new List<IWebhookHandler> { new RecordingWebhookHandler("stripe"), new UpperProvider() };

        // Act
        var act = () => new WebhookHandlerRegistry(handlers);

        // Assert
        act.Should().Throw<InvalidOperationException>();
    }

    [Theory]
    [ClassData(typeof(MalformedProviderCases))]
    public void It_should_refuse_a_handler_whose_provider_is_not_a_lowercase_id(string provider)
    {
        // Arrange
        var handlers = new List<IWebhookHandler> { new ConfigurableProvider(provider) };

        // Act
        var act = () => new WebhookHandlerRegistry(handlers);

        // Assert
        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*not a lowercase provider id*");
    }

    private sealed class UpperProvider : IWebhookHandler
    {
        public string Provider => "STRIPE";

        public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
            WebhookEnvelope envelope,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    private sealed class ConfigurableProvider(string provider) : IWebhookHandler
    {
        public string Provider { get; } = provider;

        public Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
            WebhookEnvelope envelope,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    private sealed class UnknownProviderCases : TheoryData<string?>
    {
        public UnknownProviderCases()
        {
            this.Add("paypal");
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("   ");
        }
    }

    private sealed class MalformedProviderCases : TheoryData<string>
    {
        public MalformedProviderCases()
        {
            this.Add("Stripe");
            this.Add("-stripe");
            this.Add("stripe live");
            this.Add(string.Empty);
            this.Add("  ");
        }
    }
}

public class WebhookIdempotency_KeyOf
{
    [Fact]
    public void It_should_compose_the_tenant_route_and_dedup_triple()
    {
        // Arrange
        var envelope = Envelope("tenant-1", "route-1", "native:evt-1");

        // Act
        var actual = WebhookIdempotency.KeyOf(envelope);

        // Assert
        actual.Should().Be("8:tenant-1|7:route-1|12:native:evt-1");
    }

    [Fact]
    public void It_should_give_two_triples_that_share_a_separator_run_different_keys()
    {
        // Arrange — tenant and route ids are opaque, so a separator can legitimately appear
        // inside one. A plain join would collapse these two into one dedup entry.
        var first = Envelope("a|b", "c", "native:x");
        var second = Envelope("a", "b|c", "native:x");

        // Act
        var left = WebhookIdempotency.KeyOf(first);
        var right = WebhookIdempotency.KeyOf(second);

        // Assert
        left.Should().NotBe(right);
    }

    [Fact]
    public void It_should_be_stable_across_attempts_of_one_obligation()
    {
        // Arrange
        var first = Envelope("tenant-1", "route-1", "native:evt-1", attempt: 1);
        var retry = Envelope("tenant-1", "route-1", "native:evt-1", attempt: 4);

        // Act
        var left = WebhookIdempotency.KeyOf(first);
        var right = WebhookIdempotency.KeyOf(retry);

        // Assert
        left.Should().Be(right);
    }

    private static WebhookEnvelope Envelope(string tenant, string route, string dedup, int attempt = 1) =>
        WebhookEnvelopeReader.Read(
                new WebhookEnvelopeBuilder()
                    .With("tenantId", JsonValue.Create(tenant))
                    .With("routeId", JsonValue.Create(route))
                    .With("dedupId", JsonValue.Create(dedup))
                    .WithNested("delivery", "attempt", JsonValue.Create(attempt))
                    .ToBytes())
            .Get();
}

public class StaticWebhookSecretProvider_Construct
{
    [Fact]
    public void It_should_keep_every_non_blank_key()
    {
        // Act
        var actual = new StaticWebhookSecretProvider("one", "  ", "two");

        // Assert
        actual.SigningKeys.Should().Equal(["one", "two"]);
    }

    [Theory]
    [ClassData(typeof(EmptyKeyCases))]
    public void It_should_refuse_a_key_set_that_could_never_verify_anything(string[] keys)
    {
        // Act
        var act = () => new StaticWebhookSecretProvider(keys);

        // Assert
        act.Should().Throw<ArgumentException>().WithMessage("*non-blank webhook signing key*");
    }

    private sealed class EmptyKeyCases : TheoryData<string[]>
    {
        public EmptyKeyCases()
        {
            this.Add([]);
            this.Add([string.Empty]);
            this.Add(["   ", string.Empty]);
        }
    }
}
