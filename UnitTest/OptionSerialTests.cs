using System.Text.Json;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.Diene.Results.UnitTest;

public class OptionSerialTests
{
    [Fact]
    public void It_should_create_map_chain_match_and_extract_options()
    {
        var some = Option.Some(2);
        var none = Option.None<int>();

        some.IsSome().Should().BeTrue();
        some.IsNone().Should().BeFalse();
        some.IsSome(out var value).Should().BeTrue();
        value.Should().Be(2);
        none.IsSome(out var absent).Should().BeFalse();
        absent.Should().Be(0);
        none.IsNone().Should().BeTrue();
        some.Map(x => x * 2).Should().BeSome(4);
        none.Map(x => x * 2).Should().BeNone();
        some.Then(x => Option.Some(x.ToString())).Should().BeSome("2");
        none.Then(x => Option.Some(x.ToString())).Should().BeNone();
        some.Match(x => x.ToString(), () => "none").Should().Be("2");
        none.Match(x => x.ToString(), () => "none").Should().Be("none");
        some.Get().Should().Be(2);
        some.GetOr(9).Should().Be(2);
        none.GetOr(9).Should().Be(9);
        some.GetOr(() => 9).Should().Be(2);
        none.GetOr(() => 9).Should().Be(9);
        some.ToNullable().Should().Be(2);
        none.ToNullable().Should().Be(0);
        some.OkOr("bad").Should().BeOk(2);
        none.OkOr("bad").Should().BeErr("bad");
        Option.FromNullable<string>(null).Should().BeNone();
        Option.FromNullable("value").Should().BeSome("value");
    }

    [Fact]
    public void It_should_fail_loudly_and_support_option_value_semantics()
    {
        var some = Option.Some(2);
        var twin = Option.Some(2);
        var none = Option.None<int>();

        var get = () => none.Get();
        get.Should().Throw<UnwrapException>().Which.ExpectedVariant.Should().Be("Some");
        (some == twin).Should().BeTrue();
        (some != none).Should().BeTrue();
        some.Equals((object)twin).Should().BeTrue();
        some.Equals("not option").Should().BeFalse();
        some.GetHashCode().Should().Be(twin.GetHashCode());
        some.ToString().Should().Be("Some(2)");
        none.ToString().Should().Be("None");

        var invalid = default(Option<int>);
        var inspect = () => invalid.IsSome();
        inspect.Should().Throw<InvalidResultException>();
        var equality = () => invalid.Equals(some);
        equality.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_round_trip_the_source_owned_c0_fixture()
    {
        var fixturePath = Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "monad-v1.json");
        using var document = JsonDocument.Parse(File.ReadAllText(fixturePath));
        var cases = document.RootElement.GetProperty("cases");

        var okJson = JsonSerializer.Serialize(Result.Ok<int, string>(42).ToSerial());
        var errJson = JsonSerializer.Serialize(Result.Err<int, string>("boom").ToSerial());
        var someJson = JsonSerializer.Serialize(Option.Some("value").ToSerial());
        var noneJson = JsonSerializer.Serialize(Option.None<string>().ToSerial());
        JsonElement.DeepEquals(JsonDocument.Parse(okJson).RootElement, cases.GetProperty("ok")).Should().BeTrue();
        JsonElement.DeepEquals(JsonDocument.Parse(errJson).RootElement, cases.GetProperty("err")).Should().BeTrue();
        JsonElement.DeepEquals(JsonDocument.Parse(someJson).RootElement, cases.GetProperty("some")).Should().BeTrue();
        JsonElement.DeepEquals(JsonDocument.Parse(noneJson).RootElement, cases.GetProperty("none")).Should().BeTrue();

        Result.FromSerial(JsonSerializer.Deserialize<ResultSerial<int, string>>(okJson)!).Should().BeOk(42);
        Result.FromSerial(JsonSerializer.Deserialize<ResultSerial<int, string>>(errJson)!).Should().BeErr("boom");
        Option.FromSerial(JsonSerializer.Deserialize<OptionSerial<string>>(someJson)!).Should().BeSome("value");
        Option.FromSerial(JsonSerializer.Deserialize<OptionSerial<string>>(noneJson)!).Should().BeNone();
        ResultSerial<int, string>.Ok(4).Match(value => value, _ => 0).Should().Be(4);
        ResultSerial<int, string>.Err("bad").Match(value => value, error => error.Length).Should().Be(3);
        OptionSerial<int>.Some(5).Match(value => value, () => 0).Should().Be(5);
        OptionSerial<int>.None().Match(value => value, () => 0).Should().Be(0);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[\"wat\",1]")]
    [InlineData("[\"ok\"]")]
    [InlineData("[\"ok\",1,2]")]
    public void It_should_reject_malformed_result_serial(string json)
    {
        var act = () => JsonSerializer.Deserialize<ResultSerial<int, string>>(json);
        act.Should().Throw<JsonException>();
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[\"wat\",null]")]
    [InlineData("[\"none\",1]")]
    [InlineData("[\"some\"]")]
    [InlineData("[\"some\",1,2]")]
    public void It_should_reject_malformed_option_serial(string json)
    {
        var act = () => JsonSerializer.Deserialize<OptionSerial<int>>(json);
        act.Should().Throw<JsonException>();
    }

    [Fact]
    public void Converter_factory_should_describe_its_supported_types()
    {
        var subject = new MonadSerialJsonConverterFactory();
        subject.CanConvert(typeof(ResultSerial<int, string>)).Should().BeTrue();
        subject.CanConvert(typeof(OptionSerial<int>)).Should().BeTrue();
        subject.CanConvert(typeof(string)).Should().BeFalse();
        subject.CreateConverter(typeof(ResultSerial<int, string>), new JsonSerializerOptions()).Should().NotBeNull();
        subject.CreateConverter(typeof(OptionSerial<int>), new JsonSerializerOptions()).Should().NotBeNull();
        var nullType = () => subject.CreateConverter(null!, new JsonSerializerOptions());
        nullType.Should().Throw<ArgumentNullException>();
        var nullOptions = () => subject.CreateConverter(typeof(OptionSerial<int>), null!);
        nullOptions.Should().Throw<ArgumentNullException>();

        var valueFactory = new ResultValueJsonConverterFactory();
        valueFactory.CanConvert(typeof(Result<int, string>)).Should().BeTrue();
        valueFactory.CanConvert(typeof(string)).Should().BeFalse();
        valueFactory.CreateConverter(typeof(Result<int, string>), new JsonSerializerOptions()).Should().NotBeNull();
        var nullValueType = () => valueFactory.CreateConverter(null!, new JsonSerializerOptions());
        nullValueType.Should().Throw<ArgumentNullException>();
        var nullValueOptions = () => valueFactory.CreateConverter(typeof(Result<int, string>), null!);
        nullValueOptions.Should().Throw<ArgumentNullException>();

        var serializeValue = () => JsonSerializer.Serialize(Result.Ok<int, string>(2));
        serializeValue.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
        var deserializeValue = () => JsonSerializer.Deserialize<Result<int, string>>("[\"ok\",2]");
        deserializeValue.Should().Throw<NotSupportedException>().WithMessage("*ResultSerial*");

        var optionValueFactory = new OptionValueJsonConverterFactory();
        optionValueFactory.CanConvert(typeof(Option<int>)).Should().BeTrue();
        optionValueFactory.CanConvert(typeof(string)).Should().BeFalse();
        optionValueFactory.CreateConverter(typeof(Option<int>), new JsonSerializerOptions()).Should().NotBeNull();
        var nullOptionValueType = () => optionValueFactory.CreateConverter(null!, new JsonSerializerOptions());
        nullOptionValueType.Should().Throw<ArgumentNullException>();
        var nullOptionValueOptions = () => optionValueFactory.CreateConverter(typeof(Option<int>), null!);
        nullOptionValueOptions.Should().Throw<ArgumentNullException>();

        var serializeSome = () => JsonSerializer.Serialize(Option.Some(2));
        serializeSome.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
        var serializeNone = () => JsonSerializer.Serialize(Option.None<int>());
        serializeNone.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
        var deserializeOption = () => JsonSerializer.Deserialize<Option<int>>("[\"some\",2]");
        deserializeOption.Should().Throw<NotSupportedException>().WithMessage("*OptionSerial*");

        var serializeFailure = () => JsonSerializer.Serialize(Result.Err<int, string>("bad"));
        serializeFailure.Should().Throw<NotSupportedException>().WithMessage("*ToSerial*");
    }
}
