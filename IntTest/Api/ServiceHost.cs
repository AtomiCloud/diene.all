using AtomiCloud.DotnetBase.App.Modules.Info;
using Microsoft.AspNetCore.Mvc.Testing;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The dependency-free service host: the REAL application pipeline — configuration layering,
/// options validation, versioning, routing, the problem filter, content negotiation — with no
/// container behind it. Every case reachable by substituting a domain service belongs here,
/// because a container it does not need is a container that can fail it.
/// </summary>
/// <remarks>
/// <para>
/// <b>The entry point is NOT <c>Program</c>, and that is a finding rather than a preference.</b>
/// <c>WebApplicationFactory&lt;Program&gt;</c> does not compile against this host:
/// <c>App/Program.cs</c> declares <c>public static class Program</c>, and a static type cannot be
/// used as a generic type argument (CS0718, verified by compiling it). The type argument only
/// locates the assembly and its entry point, so any non-static public type from the App assembly
/// selects the same host and the same <c>Program.Main</c>. Making <c>Program</c> a non-static
/// <c>partial class</c> is the conventional ASP.NET fix and would let this read
/// <c>&lt;Program&gt;</c> literally; that file belongs to the node controller, so it is reported
/// rather than changed.
/// </para>
/// <para>
/// <b>Settings are injected as ENVIRONMENT VARIABLES rather than through
/// <c>ConfigureAppConfiguration</c>, and that is deliberate.</b> The service builds its own
/// configuration inside <c>Program.Main</c> via <c>AddServiceConfiguration</c>, and a source added
/// by the test host does not reliably land AFTER it — so an in-memory collection loses to the YAML
/// base layer. That failure mode is nasty: the host still starts, and the only symptom is a test
/// pointed at <c>localhost</c> instead of its container, or a blank secret. The <c>ATOMI_</c>
/// environment path is the service's own highest-precedence layer, so it cannot be out-ordered and
/// it exercises the same mechanism a real landscape uses.
/// </para>
/// <para>
/// A signing key has to be supplied at all because the base layer declares
/// <c>server_engine:webhook_signing_keys</c> EMPTY — secrets are blank in YAML by convention — and
/// <c>AddAtomiWebhookSecrets</c> refuses a host with no key rather than starting one that cannot
/// verify a delivery.
/// </para>
/// </remarks>
public class ServiceHost : WebApplicationFactory<InfoController>
{
    /// <summary>The webhook signing key this host verifies against.</summary>
    public const string SigningKey = "int-test-webhook-secret";

    private const string Prefix = "ATOMI_";

    /// <summary>Creates the host and publishes its settings before anything can build it.</summary>
    public ServiceHost() => this.PublishSettings();

    /// <summary>Settings layered on top of the service's own, in CONFIGURATION key form.</summary>
    /// <returns>Configuration values, keyed exactly as the real providers key them.</returns>
    protected virtual IEnumerable<KeyValuePair<string, string?>> Settings() =>
    [
        new("server_engine:webhook_signing_keys:0", SigningKey),
    ];

    /// <summary>
    /// Publishes <see cref="Settings"/> into the process environment in the service's own
    /// <c>ATOMI_</c> form. Must run BEFORE anything touches <c>Services</c>, since that is what
    /// builds the host and reads the layers.
    /// </summary>
    protected void PublishSettings()
    {
        foreach (var setting in this.Settings())
        {
            // `postgres:MAIN:host` becomes ATOMI_POSTGRES__MAIN__HOST: `__` nests, and an indexed
            // key carries a list entry, which is the documented environment contract.
            var name = Prefix + setting.Key.Replace(":", "__", StringComparison.Ordinal).ToUpperInvariant();
            Environment.SetEnvironmentVariable(name, setting.Value);
        }
    }
}
