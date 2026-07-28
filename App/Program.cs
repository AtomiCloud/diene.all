using AtomiCloud.Diene.AuthEngine.Config;

namespace AtomiCloud.DotnetBase.App;

/// <summary>Composition root: explicit wiring of the auth engine into a service.</summary>
public static class Program
{
    /// <summary>Runs the demo, printing the composed configuration's mount and lifetimes.</summary>
    public static void Main()
    {
        var issuer = Environment.GetEnvironmentVariable("AUTH_ISSUER");
        if (string.IsNullOrWhiteSpace(issuer)) issuer = "https://idp.example.invalid";

        var endpoint = Environment.GetEnvironmentVariable("AUTH_ENDPOINT");
        if (string.IsNullOrWhiteSpace(endpoint)) endpoint = "https://idp.example.invalid";

        var config = AuthEngineDemo.BuildConfig(issuer, endpoint);

        Console.WriteLine(config.Match(
            settings =>
                $"auth engine ready: issuer {settings.Logto.Issuer}, mount {settings.Handoff.Mount}, " +
                $"access {settings.Lifetimes.Access}, refresh {settings.Lifetimes.Refresh}",
            error => $"configuration rejected -> {error}"));
    }
}
