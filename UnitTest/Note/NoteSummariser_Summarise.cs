using System.Text;
using AtomiCloud.Diene.Note;
using AtomiCloud.Diene.Note.TestHelper.Note;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class NoteSummariser_Summarise
{
    [Fact]
    public void It_should_return_the_full_line_when_within_the_limit()
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "Hello", Body = "world" };

        // Act
        var actual = subject.Summarise(input, 80);

        // Assert
        actual.Should().Be("Hello — world");
        subject.AssertSummary(input, 80, "Hello — world");
    }

    [Fact]
    public void It_should_collapse_internal_whitespace_into_single_spaces()
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "  Spaced   out  ", Body = "many\n\tgaps" };

        // Act
        var actual = subject.Summarise(input, 80);

        // Assert
        actual.Should().Be("Spaced out — many gaps");
    }

    [Fact]
    public void It_should_truncate_on_a_word_boundary_with_an_ellipsis()
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "Release", Body = "notes describe everything that changed" };

        // Act
        var actual = subject.Summarise(input, 20);

        // Assert
        actual.Should().Be("Release — notes…");
        actual.Length.Should().BeLessThanOrEqualTo(20);
    }

    [Theory]
    [ClassData(typeof(SeparatorBoundary_Data))]
    public void It_should_not_leave_a_dangling_separator_when_truncating_between_parts(int maxLength, string expected)
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "hello world", Body = "foo" };

        // Act
        var actual = subject.Summarise(input, maxLength);

        // Assert
        actual.Should().Be(expected);
        actual.Length.Should().BeLessThanOrEqualTo(maxLength);
    }

    [Theory]
    [ClassData(typeof(EmDashAtBoundary_Data))]
    public void It_should_distinguish_the_separator_from_a_content_em_dash(
        string title,
        string body,
        int maxLength,
        string expected)
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = title, Body = body };

        // Act
        var actual = subject.Summarise(input, maxLength);

        // Assert
        actual.Should().Be(expected);
        actual.Length.Should().BeLessThanOrEqualTo(maxLength);
    }

    [Theory]
    [ClassData(typeof(SurrogateBoundary_Data))]
    public void It_should_never_split_a_surrogate_pair_when_truncating(string title, int maxLength, string expected)
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = title, Body = "" };

        // Act
        var actual = subject.Summarise(input, maxLength);

        // Assert
        actual.Should().Be(expected);
        actual.Length.Should().BeLessThanOrEqualTo(maxLength);
        actual.EnumerateRunes().Should().NotContain(rune => rune == Rune.ReplacementChar);
    }

    [Fact]
    public void It_should_never_exceed_max_length_when_no_word_boundary_fits()
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "Antidisestablishmentarianism", Body = "" };

        // Act
        var actual = subject.Summarise(input, 5);

        // Assert
        actual.Should().Be("Anti…");
        actual.Length.Should().BeLessThanOrEqualTo(5);
    }

    [Theory]
    [ClassData(typeof(EmptyPart_Data))]
    public void It_should_omit_empty_parts(string title, string body, string expected)
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = title, Body = body };

        // Act
        var actual = subject.Summarise(input, 80);

        // Assert
        actual.Should().Be(expected);
    }

    [Theory]
    [ClassData(typeof(InvalidMaxLength_Data))]
    public void It_should_reject_a_non_positive_max_length(int maxLength)
    {
        // Arrange
        var subject = new NoteSummariser();
        var input = new NoteRecord { Title = "Any", Body = "thing" };

        // Act
        var act = () => subject.Summarise(input, maxLength);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    private sealed class SeparatorBoundary_Data : TheoryData<int, string>
    {
        public SeparatorBoundary_Data()
        {
            Add(14, "hello world…");
            Add(15, "hello world…");
            Add(16, "hello world…");
            Add(17, "hello world — foo");
        }
    }

    private sealed class EmDashAtBoundary_Data : TheoryData<string, string, int, string>
    {
        public EmDashAtBoundary_Data()
        {
            Add("hello", "— foo", 11, "hello…");
            Add("Quote", "— Twain", 12, "Quote…");
            Add("hello — foo", "", 9, "hello —…");
            Add("Title", "real body text", 14, "Title — real…");
        }
    }

    private sealed class SurrogateBoundary_Data : TheoryData<string, int, string>
    {
        public SurrogateBoundary_Data()
        {
            Add("😀boom", 2, "…");
            Add("a😀boom", 3, "a…");
            Add("😀 boom", 4, "😀…");
        }
    }

    private sealed class EmptyPart_Data : TheoryData<string, string, string>
    {
        public EmptyPart_Data()
        {
            Add("Only title", "", "Only title");
            Add("   ", "Body only", "Body only");
            Add("", "  \t ", "");
        }
    }

    private sealed class InvalidMaxLength_Data : TheoryData<int>
    {
        public InvalidMaxLength_Data()
        {
            Add(0);
            Add(-1);
            Add(-100);
        }
    }
}
