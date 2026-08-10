using AtomiCloud.Diene.Note;
using AtomiCloud.Diene.Note.TestHelper.Note;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class NoteAssertions_AssertSummary
{
    [Fact]
    public void It_should_accept_a_known_good_summary()
    {
        // Arrange
        var subject = new NoteSummariser();
        var record = new NoteRecord { Title = "Hello", Body = "world" };

        // Act
        var act = () => subject.AssertSummary(record, 80, "Hello — world");

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void It_should_reject_a_known_bad_summary()
    {
        // Arrange
        var subject = new NoteSummariser();
        var record = new NoteRecord { Title = "Hello", Body = "world" };

        // Act
        var act = () => subject.AssertSummary(record, 80, "wrong");

        // Assert
        act.Should().Throw<InvalidOperationException>()
            .WithMessage("Expected summary 'wrong' but found 'Hello — world'.");
    }
}
