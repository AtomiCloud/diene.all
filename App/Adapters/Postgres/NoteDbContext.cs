using Microsoft.EntityFrameworkCore;

namespace AtomiCloud.DotnetBase.App.Adapters.Postgres;

/// <summary>
/// The relational context for the fenced sample domain. Schema changes travel as real EF Core
/// migrations applied by the db-init path, never by <c>EnsureCreated</c>.
/// </summary>
/// <param name="options">Context options supplied by the composition root.</param>
public sealed class NoteDbContext(DbContextOptions<NoteDbContext> options) : DbContext(options)
{
    /// <summary>Persisted notes.</summary>
    public DbSet<NoteEntity> Notes => this.Set<NoteEntity>();

    /// <inheritdoc />
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<NoteEntity>(note =>
        {
            note.ToTable("notes");
            note.HasKey(x => x.Id);
            note.Property(x => x.Id).HasColumnName("id").HasMaxLength(64);
            note.Property(x => x.Title).HasColumnName("title").HasMaxLength(256).IsRequired();
            note.Property(x => x.Body).HasColumnName("body").IsRequired();

            // The uniqueness the domain's note_title_conflict problem reports on.
            note.HasIndex(x => x.Title).IsUnique().HasDatabaseName("ix_notes_title");
        });
    }
}
