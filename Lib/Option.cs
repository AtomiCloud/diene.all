using System.Diagnostics.CodeAnalysis;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Results;

/// <summary>An allocation-free optional value.</summary>
[JsonConverter(typeof(OptionValueJsonConverterFactory))]
public readonly struct Option<T> : IEquatable<Option<T>>
{
    private const byte SomeState = 1;
    private const byte NoneState = 2;
    private readonly byte _state;
    private readonly T? _value;

    internal Option(T value)
    {
        _state = SomeState;
        _value = value;
    }

    internal Option(bool none)
    {
        _state = none ? NoneState : throw new ArgumentOutOfRangeException(nameof(none));
        _value = default;
    }

    /// <summary>Returns whether a value is present.</summary>
    public bool IsSome()
    {
        EnsureInitialized();
        return _state == SomeState;
    }

    /// <summary>Tests for Some and extracts its value.</summary>
    public bool IsSome([MaybeNullWhen(false)] out T value)
    {
        EnsureInitialized();
        value = _value;
        return _state == SomeState;
    }

    /// <summary>Returns whether no value is present.</summary>
    public bool IsNone()
    {
        EnsureInitialized();
        return _state == NoneState;
    }

    /// <summary>Maps the present value.</summary>
    public Option<TOut> Map<TOut>(Func<T, TOut> mapper)
    {
        ArgumentNullException.ThrowIfNull(mapper);
        return IsSome() ? Option.Some(mapper(_value!)) : Option.None<TOut>();
    }

    /// <summary>Chains an Option-returning continuation.</summary>
    public Option<TOut> Then<TOut>(Func<T, Option<TOut>> continuation)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        return IsSome() ? continuation(_value!) : Option.None<TOut>();
    }

    /// <summary>Exhaustively maps either variant.</summary>
    public TOut Match<TOut>(Func<T, TOut> some, Func<TOut> none)
    {
        ArgumentNullException.ThrowIfNull(some);
        ArgumentNullException.ThrowIfNull(none);
        return IsSome() ? some(_value!) : none();
    }

    /// <summary>Gets the present value or throws <see cref="UnwrapException"/>.</summary>
    public T Get()
    {
        EnsureInitialized();
        if (_state == NoneState) throw new UnwrapException("Some", null);
        return _value!;
    }

    /// <summary>Gets the present value or returns a fallback.</summary>
    public T GetOr(T fallback) => IsSome() ? _value! : fallback;

    /// <summary>Gets the present value or computes a fallback.</summary>
    public T GetOr(Func<T> fallback)
    {
        ArgumentNullException.ThrowIfNull(fallback);
        return IsSome() ? _value! : fallback();
    }

    /// <summary>Returns the value or <see langword="null"/>.</summary>
    public T? ToNullable() => IsSome() ? _value : default;

    /// <summary>Converts Some to Success and None to Failure.</summary>
    public Result<T, E> OkOr<E>(E error) => IsSome() ? Result.Ok<T, E>(_value!) : Result.Err<T, E>(error);

    /// <summary>Converts to the explicit C0 wire representation.</summary>
    public OptionSerial<T> ToSerial() => IsSome() ? OptionSerial<T>.Some(_value!) : OptionSerial<T>.None();

    /// <inheritdoc />
    public bool Equals(Option<T> other)
    {
        EnsureInitialized();
        other.EnsureInitialized();
        return _state == other._state && (_state == NoneState || EqualityComparer<T>.Default.Equals(_value, other._value));
    }

    /// <inheritdoc />
    public override bool Equals(object? obj) => obj is Option<T> other && Equals(other);

    /// <inheritdoc />
    public override int GetHashCode()
    {
        EnsureInitialized();
        return HashCode.Combine(_state, _value);
    }

    /// <inheritdoc />
    public override string ToString()
    {
        EnsureInitialized();
        return _state == SomeState ? $"Some({_value})" : "None";
    }

    /// <summary>Determines whether two Options are equal.</summary>
    public static bool operator ==(Option<T> left, Option<T> right) => left.Equals(right);

    /// <summary>Determines whether two Options are unequal.</summary>
    public static bool operator !=(Option<T> left, Option<T> right) => !left.Equals(right);

    private void EnsureInitialized()
    {
        if (_state is not SomeState and not NoneState) throw new InvalidResultException();
    }
}

/// <summary>Factories for Options.</summary>
public static class Option
{
    /// <summary>Creates an Option containing a value.</summary>
    public static Option<T> Some<T>(T value) => new(value);

    /// <summary>Creates an empty Option.</summary>
    public static Option<T> None<T>() => new(true);

    /// <summary>Creates None for null and Some for a non-null value.</summary>
    public static Option<T> FromNullable<T>(T? value) => value is null ? None<T>() : Some(value);

    /// <summary>Creates an Option from its explicit C0 wire representation.</summary>
    public static Option<T> FromSerial<T>(OptionSerial<T> serial)
    {
        ArgumentNullException.ThrowIfNull(serial);
        return serial.Match(Some, None<T>);
    }
}
