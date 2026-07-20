using AtomiCloud.DotnetBase.App.Adapters.Redis;
using AtomiCloud.Diene.Note;
using FluentAssertions;
using StackExchange.Redis;
using Testcontainers.Redis;

namespace AtomiCloud.DotnetBase.IntTest.Adapters.Redis;

public class RedisNoteRepository_RoundTrip : IAsyncLifetime
{
    private readonly RedisContainer _redis = new RedisBuilder("redis:8.2.1-alpine")
        .Build();

    private IConnectionMultiplexer _connection = null!;

    public async ValueTask InitializeAsync()
    {
        await _redis.StartAsync();
        var options = ConfigurationOptions.Parse(_redis.GetConnectionString());
        options.AbortOnConnectFail = false;
        options.ConnectRetry = 5;
        _connection = await ConnectionMultiplexer.ConnectAsync(options);
    }

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null) await _connection.DisposeAsync();
        await _redis.DisposeAsync();
    }

    [Fact]
    public async Task It_should_persist_a_note_and_read_the_same_value_back()
    {
        // Arrange
        var subject = new RedisNoteRepository(_connection);
        var input = new NoteRecord { Title = "Round trip", Body = "stored in Redis" };

        // Act
        var saved = await subject.Save(input, TestContext.Current.CancellationToken);
        var actual = await subject.Find(saved.Id, TestContext.Current.CancellationToken);

        // Assert
        actual.Should().NotBeNull();
        actual!.Id.Should().Be(saved.Id);
        actual.Record.Should().Be(input);
    }

    [Fact]
    public async Task It_should_return_null_when_the_note_is_absent()
    {
        // Arrange
        var subject = new RedisNoteRepository(_connection);

        // Act
        var actual = await subject.Find("missing", TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeNull();
    }

    [Fact]
    public async Task It_should_reject_blank_note_ids()
    {
        // Arrange
        var subject = new RedisNoteRepository(_connection);

        // Act
        var act = async () => await subject.Find(" ", TestContext.Current.CancellationToken);

        // Assert
        await act.Should().ThrowAsync<ArgumentException>()
            .WithParameterName("id");
    }
}
