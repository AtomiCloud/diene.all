using AtomiCloud.Diene.StandardConfig.Presets;
using AtomiCloud.DotnetBase.App.Adapters.Postgres;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>Relational persistence layer of the composition root.</summary>
public static class PersistenceRegistration
{
    /// <summary>Registers the EF Core context over the <c>postgres:</c> preset.</summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServicePersistence(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddDbContext<NoteDbContext>((provider, builder) =>
        {
            var postgres = provider.GetRequiredService<IOptions<PostgresBlock>>().Value
                .Named(DomainRegistration.PrimaryConnection);
            builder.UseNpgsql(ConnectionString(postgres));
        });

        return services;
    }

    /// <summary>
    /// Builds a Npgsql connection string from a preset connection entry. The pool bounds are
    /// configuration, so a landscape can widen them without a rebuild.
    /// </summary>
    /// <param name="option">The bound, named connection.</param>
    /// <returns>A connection string.</returns>
    public static string ConnectionString(PostgresOption option)
    {
        ArgumentNullException.ThrowIfNull(option);

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = option.Host,
            Port = option.Port,
            Database = option.Database,
            Username = option.Username,
            Password = option.Password,
            SslMode = option.Ssl ? SslMode.Require : SslMode.Disable,
            MinPoolSize = option.Pool.Min,
            MaxPoolSize = option.Pool.Max,
        };

        return builder.ConnectionString;
    }
}
