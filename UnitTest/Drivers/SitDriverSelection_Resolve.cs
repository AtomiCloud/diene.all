using AtomiCloud.Diene.E2e.Drivers;
using AtomiCloud.Diene.E2e.Garden;
using FluentAssertions;

namespace AtomiCloud.Diene.E2e.UnitTest.Drivers;

public class SitDriverSelection_Resolve
{
    [Theory]
    [InlineData("inprocess", SitDriverKind.InProcess)]
    [InlineData(" INPROCESS ", SitDriverKind.InProcess)]
    [InlineData("garden", SitDriverKind.Garden)]
    public void It_should_parse_an_explicit_driver(string value, SitDriverKind expected)
    {
        SitDriverSelection.Resolve(value).Should().Be(expected);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("docker")]
    public void It_should_never_silently_choose_a_venue(string? value)
    {
        var act = () => SitDriverSelection.Resolve(value);

        act.Should().Throw<E2eHarnessException>().WithMessage("*SIT_DRIVER*");
    }
}
