namespace AtomiCloud.Diene.CoreUtils.UnitTest;

public class SlugTests
{
    [Theory]
    [InlineData("Hello, World!", "hello-world")]
    [InlineData("  Crème Brûlée  ", "creme-brulee")]
    [InlineData("ÅNGSTRÖM__unit", "angstrom-unit")]
    [InlineData("already-kebab", "already-kebab")]
    [InlineData("MiXeD CaSe 42", "mixed-case-42")]
    [InlineData("---leading and trailing---", "leading-and-trailing")]
    [InlineData("ß", "")]
    [InlineData("", "")]
    [InlineData("!!!", "")]
    public void It_should_fold_input_into_a_deterministic_kebab_slug(string input, string expected) =>
        Slug.Slugify(input).Should().Be(expected);

    [Fact]
    public void It_should_reject_a_null_input() =>
        FluentActions.Invoking(() => Slug.Slugify(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void It_should_compose_a_namespaced_key_from_slugified_parts() =>
        Slug.NamespacedKey("AtomiCloud", "Express Parcel").Should().BeOk("atomicloud:express-parcel");

    [Fact]
    public void It_should_reject_a_namespace_that_slugifies_to_empty() =>
        Slug.NamespacedKey("!!!", "key").Should().BeErr(new KeyError("namespace must not be empty", "!!!"));

    [Fact]
    public void It_should_reject_a_key_that_slugifies_to_empty() =>
        Slug.NamespacedKey("ns", "   ").Should().BeErr(new KeyError("key must not be empty", "   "));

    [Fact]
    public void It_should_reject_null_namespaced_key_parts()
    {
        FluentActions.Invoking(() => Slug.NamespacedKey(null!, "key")).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => Slug.NamespacedKey("ns", null!)).Should().Throw<ArgumentNullException>();
    }
}
