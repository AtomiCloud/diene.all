namespace AtomiCloud.DotnetBase.UnitTest;

public class KeyedBlockTests
{
    private static IReadOnlyDictionary<string, CacheOption> Block(params string[] names) =>
        names.ToDictionary(name => name, _ => new CacheOption { Host = "localhost", Port = 6379 }, StringComparer.Ordinal);

    [Fact]
    public void It_should_find_a_connection_by_its_exact_key()
    {
        var found = Block("main").Find("main");

        found.IsSome(out var entry).Should().BeTrue();
        entry!.Port.Should().Be(6379);
    }

    [Fact]
    public void It_should_find_a_connection_by_its_authored_uppercase_name()
    {
        // The config lib folded MAIN to main before the binder ran; a service still writes
        // MAIN, because MAIN is what R14 told it to author.
        Block("main").Find("MAIN").IsSome().Should().BeTrue();
    }

    [Fact]
    public void It_should_return_none_for_an_absent_connection() =>
        Block("main").Find("REPLICA").IsNone().Should().BeTrue();

    [Fact]
    public void It_should_reject_a_null_block()
    {
        var find = () => KeyedBlock.Find<CacheOption>(null!, "MAIN");
        find.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_key()
    {
        var find = () => Block("main").Find(null!);
        find.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_resolve_a_named_connection() =>
        Block("main").Named("MAIN").Port.Should().Be(6379);

    [Fact]
    public void It_should_name_the_known_keys_when_a_connection_is_absent()
    {
        var named = () => Block("replica", "main").Named("ANALYTICS");

        named.Should()
            .Throw<StandardConfigException>()
            .WithMessage("*ANALYTICS*")
            .WithMessage("*main, replica*");
    }

    [Fact]
    public void It_should_say_so_when_no_connection_is_registered_at_all()
    {
        var named = () => Block().Named("MAIN");

        named.Should().Throw<StandardConfigException>().WithMessage("*(none registered)*");
    }

    [Fact]
    public void It_should_carry_its_message() =>
        new StandardConfigException("boom").Message.Should().Be("boom");
}
