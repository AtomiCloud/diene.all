namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// Assert-the-asserter: every shipped assertion is proven to PASS on a known-good subject and
/// FAIL on a known-bad one.
/// </summary>
/// <remarks>
/// An assertion helper that cannot fail is worse than no helper: it makes a consumer's whole
/// suite green for the wrong reason. The failure direction is the half that matters, so it is
/// tested first and for every helper.
/// </remarks>
public class PresetAssertionsTests
{
    private static CacheBlock Block(params string[] names)
    {
        var block = new CacheBlock();
        foreach (var name in names) block[name] = new CacheOption { Host = "localhost", Port = 6379 };
        return block;
    }

    // ── HaveConnection ──────────────────────────────────────────────────────────────────

    [Fact]
    public void HaveConnection_should_pass_for_a_present_connection() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main")).ShouldAsPresetBlock().HaveConnection("main");

    [Fact]
    public void HaveConnection_should_pass_for_the_authored_uppercase_name() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main")).ShouldAsPresetBlock().HaveConnection("MAIN");

    [Fact]
    public void HaveConnection_should_continue_on_the_entry_it_found() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main"))
            .ShouldAsPresetBlock()
            .HaveConnection("MAIN")
            .Which.Port.Should()
            .Be(6379);

    [Fact]
    public void HaveConnection_should_fail_for_an_absent_connection()
    {
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)Block("main")).ShouldAsPresetBlock().HaveConnection("REPLICA");

        assert.Should().Throw<Exception>().WithMessage("*REPLICA*").WithMessage("*main*");
    }

    [Fact]
    public void HaveConnection_should_fail_for_a_null_block()
    {
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)null!).ShouldAsPresetBlock().HaveConnection("MAIN");

        assert.Should().Throw<Exception>().WithMessage("*MAIN*");
    }

    [Fact]
    public void HaveConnection_should_yield_no_entry_when_it_failed_inside_a_scope()
    {
        // Inside an AssertionScope a failure is collected rather than thrown, so the chain
        // keeps running. `.Which` must then be harmless rather than handing back a stale entry.
        var assert = () =>
        {
            using var scope = new FluentAssertions.Execution.AssertionScope();
            ((IReadOnlyDictionary<string, CacheOption>)Block("main"))
                .ShouldAsPresetBlock()
                .HaveConnection("REPLICA")
                .Which.Should()
                .BeNull();
        };

        assert.Should().Throw<Exception>().WithMessage("*REPLICA*");
    }

    [Fact]
    public void HaveConnection_should_carry_the_caller_reason()
    {
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)Block("main"))
            .ShouldAsPresetBlock()
            .HaveConnection("REPLICA", "the read path needs {0}", "REPLICA");

        assert.Should().Throw<Exception>().WithMessage("*the read path needs REPLICA*");
    }

    // ── HaveWellFormedConnectionNames ───────────────────────────────────────────────────

    [Fact]
    public void HaveWellFormedConnectionNames_should_pass_for_bound_names() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main", "replica"))
            .ShouldAsPresetBlock()
            .HaveWellFormedConnectionNames();

    [Fact]
    public void HaveWellFormedConnectionNames_should_fail_on_punctuation()
    {
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)Block("my@pool"))
            .ShouldAsPresetBlock()
            .HaveWellFormedConnectionNames();

        assert.Should().Throw<Exception>().WithMessage("*my@pool*");
    }

    [Fact]
    public void HaveWellFormedConnectionNames_should_pass_vacuously_for_a_null_block() =>
        ((IReadOnlyDictionary<string, CacheOption>)null!).ShouldAsPresetBlock().HaveWellFormedConnectionNames();

    // ── BeValidAgainst ──────────────────────────────────────────────────────────────────

    [Fact]
    public void BeValidAgainst_should_pass_for_a_valid_block() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main")).ShouldAsPresetBlock().BeValidAgainst(new CacheBlockValidator());

    [Fact]
    public void BeValidAgainst_should_fail_and_report_the_validator_messages()
    {
        var block = Block("main");
        block["main"].Host = "";

        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)block)
            .ShouldAsPresetBlock()
            .BeValidAgainst(new CacheBlockValidator());

        assert.Should().Throw<Exception>().WithMessage("*Host*");
    }

    [Fact]
    public void BeValidAgainst_should_treat_a_null_block_as_an_empty_one() =>
        ((IReadOnlyDictionary<string, CacheOption>)null!).ShouldAsPresetBlock().BeValidAgainst(new CacheBlockValidator());

    [Fact]
    public void BeValidAgainst_should_reject_a_null_validator()
    {
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)Block("main")).ShouldAsPresetBlock().BeValidAgainst<CacheBlock>(null!);

        assert.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void BeValidAgainst_should_carry_the_caller_reason()
    {
        var block = Block("main");
        block["main"].Port = 0;

        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)block)
            .ShouldAsPresetBlock()
            .BeValidAgainst(new CacheBlockValidator(), "the {0} preset is composed here", "cache");

        assert.Should().Throw<Exception>().WithMessage("*the cache preset is composed here*");
    }

    [Fact]
    public void It_should_chain_assertions_over_one_block() =>
        ((IReadOnlyDictionary<string, CacheOption>)Block("main"))
            .ShouldAsPresetBlock()
            .HaveWellFormedConnectionNames()
            .And.Subject.ShouldAsPresetBlock()
            .BeValidAgainst(new CacheBlockValidator());

    [Fact]
    public void It_should_name_the_subject_in_every_failure_message()
    {
        // FluentAssertions reads Identifier only through its own failure path, so the property
        // is proven live rather than by reading it back off the assertions object.
        var assert = () => ((IReadOnlyDictionary<string, CacheOption>)Block("my@pool"))
            .ShouldAsPresetBlock()
            .HaveWellFormedConnectionNames();

        assert.Should().Throw<Exception>().WithMessage("*preset block*");
    }
}
