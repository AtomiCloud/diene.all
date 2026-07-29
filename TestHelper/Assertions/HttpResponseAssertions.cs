using System.Net;

namespace AtomiCloud.Diene.E2e.TestHelper.Assertions;

/// <summary>Black-box HTTP assertions that retain the response for further inspection.</summary>
public static class HttpResponseAssertions
{
    /// <summary>Requires one exact status code rather than accepting a broad success range.</summary>
    public static HttpResponseMessage ShouldHaveStatus(
        this HttpResponseMessage response,
        HttpStatusCode expected)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (response.StatusCode != expected)
        {
            throw new E2eAssertionException(
                $"Expected HTTP status {(int)expected}, but received {(int)response.StatusCode}.");
        }

        return response;
    }
}
