using AtomiCloud.Diene.Config.TestHelper;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Meta tier — subject is the TestHelper, not the library.
/// </summary>
/// <remarks>
/// Fixture/builder invariants: a fake layer that keyed itself differently from the real YAML
/// provider would let a consumer's test pass while production fails, which is the one failure
/// mode a fake must not have.
/// </remarks>
public class MetaFakeConfigLayerTests
{
    private static IConfiguration Build(FakeConfigLayer layer) =>
        new ConfigurationBuilder().Add(layer).Build();

    [Fact]
    public void A_fake_layer_keys_itself_exactly_as_the_real_yaml_provider_does()
    {
        var layer = new FakeConfigLayer().Set("error_portal:signing-key", "value");

        layer.Values.Should().ContainKey("errorportal:signingkey");
    }

    [Theory]
    [InlineData("error_portal:host")]
    [InlineData("ErrorPortal:Host")]
    [InlineData("error-portal:host")]
    public void Any_spelling_a_consumer_writes_reaches_the_same_key(string spelling) =>
        Build(new FakeConfigLayer().Set(spelling, "alpha"))["errorportal:host"].Should().Be("alpha");

    [Fact]
    public void Declare_puts_the_key_in_the_layer_with_no_value()
    {
        var config = Build(new FakeConfigLayer().Declare("error_portal:signing_key"));

        config.AsEnumerable().Select(pair => pair.Key).Should().Contain("errorportal:signingkey");
        config["errorportal:signingkey"].Should().BeNull();
    }

    [Fact]
    public void SetAll_takes_a_whole_layer_at_once()
    {
        var layer = new FakeConfigLayer().SetAll(new Dictionary<string, string?>
        {
            ["error_portal:host"] = "alpha",
            ["error_portal:scheme"] = "https",
        });

        Build(layer)["errorportal:host"].Should().Be("alpha");
        Build(layer)["errorportal:scheme"].Should().Be("https");
    }

    [Fact]
    public void Setting_the_same_key_twice_keeps_the_last_write() =>
        Build(new FakeConfigLayer().Set("host", "first").Set("host", "second"))["host"]
            .Should().Be("second");

    [Fact]
    public void Every_builder_call_returns_the_layer_so_calls_chain()
    {
        var layer = new FakeConfigLayer();

        layer.Set("a", "1").Should().BeSameAs(layer);
        layer.Declare("b").Should().BeSameAs(layer);
        layer.SetAll([]).Should().BeSameAs(layer);
    }

    [Fact]
    public void Set_rejects_a_blank_key() =>
        FluentActions.Invoking(() => new FakeConfigLayer().Set("  ", "v"))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void SetAll_rejects_null_values() =>
        FluentActions.Invoking(() => new FakeConfigLayer().SetAll(null!))
            .Should().Throw<ArgumentNullException>();
}
