using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.Results.App;

/// <summary>Minimal consumer demonstrating railway composition.</summary>
public static class Program
{
    /// <summary>Runs the sample.</summary>
    public static void Main()
    {
        Result<int, string> parsed = Result.Ok<int, string>(21);
        var message = parsed
            .Map(value => value * 2)
            .Match(value => $"Success: {value}", error => $"Failure: {error}");
        Console.WriteLine(message);
    }
}
