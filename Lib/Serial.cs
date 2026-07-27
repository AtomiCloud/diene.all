using System.Text.Json;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Results;

/// <summary>The explicit C0 Result wire DU: <c>["ok", value]</c> or <c>["err", error]</c>.</summary>
[JsonConverter(typeof(MonadSerialJsonConverterFactory))]
public sealed class ResultSerial<T, E>
{
    private readonly byte _state;
    private readonly T? _value;
    private readonly E? _error;

    private ResultSerial(T value)
    {
        _state = 1;
        _value = value;
    }

    private ResultSerial(E error)
    {
        _state = 2;
        _error = error;
    }

    /// <summary>Creates an Ok serial value.</summary>
    public static ResultSerial<T, E> Ok(T value) => new(value);

    /// <summary>Creates an Err serial value.</summary>
    public static ResultSerial<T, E> Err(E error) => new(error);

    /// <summary>Exhaustively maps either serial variant.</summary>
    public TOut Match<TOut>(Func<T, TOut> ok, Func<E, TOut> err)
    {
        ArgumentNullException.ThrowIfNull(ok);
        ArgumentNullException.ThrowIfNull(err);
        return _state == 1 ? ok(_value!) : err(_error!);
    }
}

/// <summary>The explicit C0 Option wire DU: <c>["some", value]</c> or <c>["none", null]</c>.</summary>
[JsonConverter(typeof(MonadSerialJsonConverterFactory))]
public sealed class OptionSerial<T>
{
    private readonly bool _some;
    private readonly T? _value;

    private OptionSerial(T value)
    {
        _some = true;
        _value = value;
    }

    private OptionSerial() { }

    /// <summary>Creates a Some serial value.</summary>
    public static OptionSerial<T> Some(T value) => new(value);

    /// <summary>Creates a None serial value.</summary>
    public static OptionSerial<T> None() => new();

    /// <summary>Exhaustively maps either serial variant.</summary>
    public TOut Match<TOut>(Func<T, TOut> some, Func<TOut> none)
    {
        ArgumentNullException.ThrowIfNull(some);
        ArgumentNullException.ThrowIfNull(none);
        return _some ? some(_value!) : none();
    }
}

/// <summary>Creates the closed generic converters for C0 monad serial types.</summary>
public sealed class MonadSerialJsonConverterFactory : JsonConverterFactory
{
    /// <inheritdoc />
    public override bool CanConvert(Type typeToConvert) =>
        typeToConvert.IsGenericType &&
        (typeToConvert.GetGenericTypeDefinition() == typeof(ResultSerial<,>) ||
         typeToConvert.GetGenericTypeDefinition() == typeof(OptionSerial<>));

    /// <inheritdoc />
    public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        ArgumentNullException.ThrowIfNull(options);
        var generic = typeToConvert.GetGenericTypeDefinition();
        var converter = generic == typeof(ResultSerial<,>)
            ? typeof(ResultSerialJsonConverter<,>).MakeGenericType(typeToConvert.GetGenericArguments())
            : typeof(OptionSerialJsonConverter<>).MakeGenericType(typeToConvert.GetGenericArguments());
        return (JsonConverter)Activator.CreateInstance(converter)!;
    }

    private sealed class ResultSerialJsonConverter<T, E> : JsonConverter<ResultSerial<T, E>>
    {
        public override ResultSerial<T, E> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            Require(ref reader, JsonTokenType.StartArray);
            RequireRead(ref reader, JsonTokenType.String);
            var tag = reader.GetString();
            if (!reader.Read()) throw new JsonException("The Result tuple is missing its value.");
            ResultSerial<T, E> serial = tag switch
            {
                "ok" => ResultSerial<T, E>.Ok(JsonSerializer.Deserialize<T>(ref reader, options)!),
                "err" => ResultSerial<T, E>.Err(JsonSerializer.Deserialize<E>(ref reader, options)!),
                _ => throw new JsonException($"Unknown Result tag '{tag}'."),
            };
            RequireRead(ref reader, JsonTokenType.EndArray);
            return serial;
        }

        public override void Write(Utf8JsonWriter writer, ResultSerial<T, E> value, JsonSerializerOptions options)
        {
            writer.WriteStartArray();
            value.Match(
                ok => { writer.WriteStringValue("ok"); JsonSerializer.Serialize(writer, ok, options); return 0; },
                err => { writer.WriteStringValue("err"); JsonSerializer.Serialize(writer, err, options); return 0; });
            writer.WriteEndArray();
        }
    }

    private sealed class OptionSerialJsonConverter<T> : JsonConverter<OptionSerial<T>>
    {
        public override OptionSerial<T> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            Require(ref reader, JsonTokenType.StartArray);
            RequireRead(ref reader, JsonTokenType.String);
            var tag = reader.GetString();
            if (!reader.Read()) throw new JsonException("The Option tuple is missing its value.");
            OptionSerial<T> serial;
            if (tag == "some")
            {
                serial = OptionSerial<T>.Some(JsonSerializer.Deserialize<T>(ref reader, options)!);
            }
            else if (tag == "none" && reader.TokenType == JsonTokenType.Null)
            {
                serial = OptionSerial<T>.None();
            }
            else
            {
                throw new JsonException($"Unknown or malformed Option tag '{tag}'.");
            }

            RequireRead(ref reader, JsonTokenType.EndArray);
            return serial;
        }

        public override void Write(Utf8JsonWriter writer, OptionSerial<T> value, JsonSerializerOptions options)
        {
            writer.WriteStartArray();
            value.Match(
                some => { writer.WriteStringValue("some"); JsonSerializer.Serialize(writer, some, options); return 0; },
                () => { writer.WriteStringValue("none"); writer.WriteNullValue(); return 0; });
            writer.WriteEndArray();
        }
    }

    private static void RequireRead(ref Utf8JsonReader reader, JsonTokenType expected)
    {
        if (!reader.Read()) throw new JsonException($"Expected {expected}, but the JSON ended.");
        Require(ref reader, expected);
    }

    private static void Require(ref Utf8JsonReader reader, JsonTokenType expected)
    {
        if (reader.TokenType != expected) throw new JsonException($"Expected {expected}, found {reader.TokenType}.");
    }
}
