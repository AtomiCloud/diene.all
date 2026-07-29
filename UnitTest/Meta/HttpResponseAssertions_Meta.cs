using System.Net;
using AtomiCloud.Diene.E2e.TestHelper.Assertions;
using FluentAssertions;

namespace AtomiCloud.Diene.E2e.UnitTest.Meta;

public class HttpResponseAssertions_Meta
{
    [Fact]
    public void It_should_accept_the_exact_expected_status()
    {
        using var response = new HttpResponseMessage(HttpStatusCode.MisdirectedRequest);

        var actual = response.ShouldHaveStatus(HttpStatusCode.MisdirectedRequest);

        actual.Should().BeSameAs(response);
    }

    [Fact]
    public void It_should_refuse_a_plausible_wrong_status()
    {
        using var response = new HttpResponseMessage(HttpStatusCode.NotFound);

        var act = () => response.ShouldHaveStatus(HttpStatusCode.MisdirectedRequest);

        act.Should().Throw<E2eAssertionException>()
            .WithMessage("*421*404*");
    }

    [Fact]
    public void It_should_refuse_a_null_response()
    {
        var act = () => HttpResponseAssertions.ShouldHaveStatus(
            null!,
            HttpStatusCode.OK);

        act.Should().Throw<ArgumentNullException>();
    }
}
