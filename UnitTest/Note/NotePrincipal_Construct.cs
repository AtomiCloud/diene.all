using AtomiCloud.Diene.Note;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class NotePrincipal_Construct
{
    [Fact]
    public void It_should_pair_a_stable_identity_with_its_record()
    {
        // Arrange
        var record = new NoteRecord { Title = "Title", Body = "Body" };

        // Act
        var actual = new NotePrincipal { Id = "note-1", Record = record };

        // Assert
        actual.Id.Should().Be("note-1");
        actual.Record.Should().BeSameAs(record);
    }

    [Fact]
    public void It_should_compare_by_value()
    {
        // Arrange
        var record = new NoteRecord { Title = "Title", Body = "Body" };
        var subject = new NotePrincipal { Id = "note-1", Record = record };

        // Act
        var twin = new NotePrincipal { Id = "note-1", Record = new NoteRecord { Title = "Title", Body = "Body" } };

        // Assert
        subject.Should().Be(twin);
    }
}
