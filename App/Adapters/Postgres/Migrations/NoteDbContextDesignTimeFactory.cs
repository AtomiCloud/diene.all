using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.DotnetBase.App.StartUp.Registration;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.App.Adapters.Postgres.Migrations;

/// <summary>
/// Supplies <see cref="NoteDbContext"/> to the EF Core command-line tools at DESIGN time only.
/// Nothing at runtime resolves this.
/// </summary>
/// <remarks>
/// <para>
/// It exists because <c>dotnet ef</c> obtains a context by invoking this assembly's entry point
/// and reading the host it builds, and this service's entry point deliberately refuses to build
/// one for an unrecognised argument: <c>RunModeSelection.TryResolve</c> treats an unknown mode as
/// an error so that a typo in a Job's args cannot silently start a web host. That is the correct
/// runtime posture — a Job named <c>db-innit</c> must fail, not serve — but it means the tools
/// see <c>unknown run mode; expected 'server' or 'db-init'</c> and then
/// <c>the entry point exited without ever building an IHost</c>.
/// </para>
/// <para>
/// This factory is the sanctioned way out, and it is strictly better than loosening the run-mode
/// check: the refusal keeps its teeth, and design-time tooling stops depending on how the process
/// happens to parse arguments.
/// </para>
/// <para>
/// The connection string is READ FROM THE SAME LAYERED CONFIGURATION the service uses, through the
/// same <see cref="PersistenceRegistration.ConnectionString"/> helper, rather than hardcoded. A
/// literal here would be a second source of truth that the rebrand gate could not see, and it
/// would drift the moment the preset changed.
/// </para>
/// </remarks>
public sealed class NoteDbContextDesignTimeFactory : IDesignTimeDbContextFactory<NoteDbContext>
{
    /// <summary>Builds a context for the EF Core tools.</summary>
    /// <param name="args">Arguments passed by the tools. Unused; the layers carry the settings.</param>
    /// <returns>A context pointed at the configured primary connection.</returns>
    public NoteDbContext CreateDbContext(string[] args)
    {
        var configuration = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddServiceConfiguration(landscape: string.Empty)
            .Build();

        var postgres = configuration
            .GetSection($"{PostgresOption.Key}:{DomainRegistration.PrimaryConnection}")
            .Get<PostgresOption>() ?? new PostgresOption();

        var builder = new DbContextOptionsBuilder<NoteDbContext>()
            .UseNpgsql(PersistenceRegistration.ConnectionString(postgres));

        return new NoteDbContext(builder.Options);
    }
}
