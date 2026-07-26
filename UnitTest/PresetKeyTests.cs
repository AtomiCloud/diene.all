namespace AtomiCloud.DotnetBase.UnitTest;

public class PresetKeyTests
{
    [Theory]
    [InlineData("MAIN")]
    [InlineData("REPLICA")]
    [InlineData("READ_REPLICA")]
    [InlineData("POOL2")]
    public void It_should_accept_authored_uppercase_names(string name) =>
        PresetKey.IsValid(name).Should().BeTrue();

    [Theory]
    [InlineData("main")]
    [InlineData("Main")]
    [InlineData("_MAIN")]
    [InlineData("2MAIN")]
    [InlineData("MY-POOL")]
    [InlineData("")]
    [InlineData(null)]
    public void It_should_reject_names_that_break_the_authored_contract(string? name) =>
        PresetKey.IsValid(name).Should().BeFalse();

    [Theory]
    [InlineData("main")]
    [InlineData("readreplica")]
    [InlineData("pool2")]
    public void It_should_accept_bound_names_the_canonical_rule_could_have_produced(string name) =>
        PresetKey.IsBoundNameValid(name).Should().BeTrue();

    [Theory]
    [InlineData("my@pool")]
    [InlineData("2main")]
    [InlineData("")]
    [InlineData(null)]
    public void It_should_reject_bound_names_no_valid_author_could_produce(string? name) =>
        PresetKey.IsBoundNameValid(name).Should().BeFalse();

    [Theory]
    [InlineData("MAIN")]
    [InlineData("main")]
    [InlineData("READ_REPLICA")]
    [InlineData("readreplica")]
    public void It_should_accept_either_spelling_a_validator_can_legitimately_see(string name) =>
        PresetKey.IsAcceptable(name).Should().BeTrue();

    [Theory]
    [InlineData("Main")]
    [InlineData("my@pool")]
    [InlineData("2main")]
    [InlineData("read_replica")]
    [InlineData("")]
    [InlineData(null)]
    public void It_should_reject_a_name_that_is_neither_authored_nor_bound(string? name) =>
        PresetKey.IsAcceptable(name).Should().BeFalse();

    [Fact]
    public void It_should_keep_the_two_patterns_distinct()
    {
        // The whole point of the split: the authored contract is stricter than what survives
        // binding, so conflating them would silently pass lowercase authoring.
        PresetKey.Pattern.Should().NotBe(PresetKey.BoundPattern);
        PresetKey.IsValid("MAIN").Should().BeTrue();
        PresetKey.IsBoundNameValid("MAIN").Should().BeFalse();
    }
}
