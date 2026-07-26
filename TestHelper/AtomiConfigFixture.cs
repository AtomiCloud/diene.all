using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace AtomiCloud.Diene.Config.TestHelper;

/// <summary>
/// Builds the full C0 §3 layer stack out of fakes, so a consumer can test what its options
/// bind to and whether it fails fast — without writing YAML files to disk.
/// </summary>
/// <remarks>
/// Layers are added in precedence order (base → landscape → environment), which is the whole
/// point: this fixture is the only cheap way to prove that a landscape overlay beats a base
/// default and that an env var beats both.
/// </remarks>
public sealed class AtomiConfigFixture
{
    private readonly FakeConfigLayer _base = new();
    private readonly FakeConfigLayer _landscape = new();
    private readonly Dictionary<string, string?> _environment = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>The env prefix the fake environment layer is read under.</summary>
    public string EnvPrefix { get; init; } = "ATOMI_";

    /// <summary>Sets a key in the base layer — the full-defaults layer.</summary>
    public AtomiConfigFixture WithBase(string key, string? value)
    {
        _base.Set(key, value);
        return this;
    }

    /// <summary>Sets a key in the sparse landscape overlay.</summary>
    public AtomiConfigFixture WithLandscape(string key, string? value)
    {
        _landscape.Set(key, value);
        return this;
    }

    /// <summary>
    /// Sets an environment variable, named WITHOUT the prefix — the fixture applies it. Use
    /// <c>__</c> for nesting and indexed suffixes for lists, exactly as in a real deployment.
    /// </summary>
    public AtomiConfigFixture WithEnvironment(string name, string? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        _environment[EnvPrefix + name] = value;
        return this;
    }

    /// <summary>
    /// Declares a key as blank in the base layer and supplies its value through the
    /// environment — the secrets convention, exercised end to end.
    /// </summary>
    public AtomiConfigFixture WithSecret(string key, string environmentName, string value)
    {
        _base.Declare(key);
        return WithEnvironment(environmentName, value);
    }

    /// <summary>Builds the merged configuration.</summary>
    public IConfiguration Build() => new ConfigurationBuilder()
        .Add(_base)
        .Add(_landscape)
        .AddAtomiEnvironmentVariables(EnvPrefix, _environment)
        .Build();

    /// <summary>
    /// Builds a service provider over the merged configuration, with
    /// <paramref name="register" /> describing the option blocks under test.
    /// </summary>
    public ServiceProvider BuildProvider(Action<IServiceCollection> register)
    {
        ArgumentNullException.ThrowIfNull(register);

        var services = new ServiceCollection();
        services.AddSingleton(Build());
        register(services);
        return services.BuildServiceProvider();
    }

    /// <summary>
    /// Resolves an option block, returning the validation failure instead of throwing so a
    /// fail-fast test reads as an assertion on a value rather than on an exception.
    /// </summary>
    public Result<T, string> Resolve<T>(Action<IServiceCollection> register)
        where T : class
    {
        using var provider = BuildProvider(register);
        try
        {
            return Result.Ok<T, string>(provider.GetRequiredService<IOptions<T>>().Value);
        }
        catch (OptionsValidationException exception)
        {
            return Result.Err<T, string>(string.Join("; ", exception.Failures));
        }
    }
}
