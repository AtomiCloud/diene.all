using AtomiCloud.DotnetBase.App.Modules.Info;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The dependency-free service host: the REAL application pipeline — configuration layering,
/// options validation, versioning, routing, the problem filter, content negotiation — with no
/// container behind it. Every case that can be reached by substituting a domain service belongs
/// here, because a container it does not need is a container that can fail it.
/// </summary>
/// <remarks>
/// <para>
/// <b>The entry point is NOT <c>Program</c>, and that is a finding rather than a preference.</b>
/// <c>WebApplicationFactory&lt;Program&gt;</c> does not compile against this host:
/// <c>App/Program.cs</c> declares <c>public static class Program</c>, and a static type cannot be
/// used as a generic type argument (CS0718, verified by compiling it). The type argument is only
/// used to locate the assembly and its entry point, so any non-static public type from the App
/// assembly selects the same host and the same <c>Program.Main</c>. Making <c>Program</c> a
/// non-static <c>partial class</c> is the conventional ASP.NET fix and would let this read
/// <c>&lt;Program&gt;</c> literally; that file is owned by the node controller, so it is reported
/// rather than changed here.
/// </para>
/// <para>
/// The signing key must be supplied because the base configuration layer declares
/// <c>server_engine:webhook_signing_keys</c> EMPTY — secrets are blank in YAML by convention —
/// and <c>AddAtomiWebhookSecrets</c> refuses a host with no key rather than starting one that
/// cannot verify a delivery. Supplying it through configuration rather than a service override is
/// deliberate: it exercises the same layering a landscape uses.
/// </para>
/// </remarks>
public class ServiceHost : WebApplicationFactory<InfoController>
{
    /// <summary>The webhook signing key this host verifies against.</summary>
    public const string SigningKey = "int-test-webhook-secret";

    /// <summary>Configuration this host adds on top of the service's own layers.</summary>
    /// <returns>Configuration values, keyed exactly as the real providers key them.</returns>
    protected virtual IEnumerable<KeyValuePair<string, string?>> Settings() =>
    [
        new("server_engine:webhook_signing_keys:0", SigningKey),
    ];

    /// <inheritdoc />
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);
        builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(this.Settings()));
    }
}
