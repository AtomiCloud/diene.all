namespace AtomiCloud.Diene.Interfaces.UnitTest.Meta;

/// <summary>
/// META tier — the published path policy of the in-memory filesystem. Consumers
/// writing their own fake read this policy, so it is pinned.
/// </summary>
public class VfsPathTests
{
    [Theory]
    [InlineData("/a/b", "/a/b")]
    [InlineData("a/b", "/a/b")]
    [InlineData("/a/b/", "/a/b")]
    [InlineData("//a//b//", "/a/b")]
    [InlineData("\\a\\b", "/a/b")]
    [InlineData("/", "/")]
    [InlineData("", "/")]
    [InlineData("   ", "/")]
    public void It_should_normalize_separators_and_trailing_slashes(string path, string expected)
    {
        VfsPath.Normalize(path).Should().Be(expected);
    }

    [Fact]
    public void It_should_reject_a_null_path()
    {
        var act = () => VfsPath.Normalize(null!);

        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_publish_the_root()
    {
        VfsPath.Root.Should().Be("/");
    }

    [Theory]
    [InlineData("/a/b/c", "/a/b")]
    [InlineData("/a", "/")]
    public void It_should_resolve_parents(string path, string expected)
    {
        VfsPath.Parent(path).Should().BeSome(expected);
    }

    [Fact]
    public void It_should_report_no_parent_at_the_root()
    {
        VfsPath.Parent("/").IsNone().Should().BeTrue();
    }

    [Theory]
    [InlineData("/a/b", "/a", true)]
    [InlineData("/a/b/c", "/a", true)]
    [InlineData("/a", "/a", false)]
    [InlineData("/ab", "/a", false)]
    [InlineData("/a", "/", true)]
    [InlineData("/", "/", false)]
    public void It_should_decide_descent(string candidate, string ancestor, bool expected)
    {
        VfsPath.IsBelow(candidate, ancestor).Should().Be(expected);
    }

    [Theory]
    [InlineData("/a/b", "/a", true)]
    [InlineData("/a/b/c", "/a", false)]
    [InlineData("/a", "/", true)]
    [InlineData("/a", "/a", false)]
    public void It_should_decide_direct_children(string candidate, string parent, bool expected)
    {
        VfsPath.IsDirectChild(candidate, parent).Should().Be(expected);
    }
}
