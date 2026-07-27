using System.Diagnostics.CodeAnalysis;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Results;

/// <summary>An allocation-free success-or-failure value with a typed error channel.</summary>
[JsonConverter(typeof(ResultValueJsonConverterFactory))]
public readonly struct Result<T, E> : IEquatable<Result<T, E>>
{
    private const byte SuccessState = 1;
    private const byte FailureState = 2;
    private readonly byte _state;
    private readonly T? _value;
    private readonly E? _error;

    internal Result(T value)
    {
        _state = SuccessState;
        _value = value;
        _error = default;
    }

    internal Result(E error)
    {
        _state = FailureState;
        _value = default;
        _error = error;
    }

    /// <summary>Returns whether this result is successful.</summary>
    public bool IsSuccess()
    {
        EnsureInitialized();
        return _state == SuccessState;
    }

    /// <summary>Tests for success and extracts the success value.</summary>
    public bool IsSuccess([MaybeNullWhen(false)] out T success)
    {
        EnsureInitialized();
        success = _value;
        return _state == SuccessState;
    }

    /// <summary>Returns whether this result is a failure.</summary>
    public bool IsFailure()
    {
        EnsureInitialized();
        return _state == FailureState;
    }

    /// <summary>Tests for failure and extracts the failure value.</summary>
    public bool IsFailure([MaybeNullWhen(false)] out E error)
    {
        EnsureInitialized();
        error = _error;
        return _state == FailureState;
    }

    /// <summary>Maps a successful value. Callback exceptions are not captured.</summary>
    public Result<TOut, E> Map<TOut>(Func<T, TOut> mapper)
    {
        ArgumentNullException.ThrowIfNull(mapper);
        return IsSuccess() ? Result.Ok<TOut, E>(mapper(_value!)) : Result.Err<TOut, E>(_error!);
    }

    /// <summary>Maps a failure value. Callback exceptions are not captured.</summary>
    public Result<T, EOut> MapFailure<EOut>(Func<E, EOut> mapper)
    {
        ArgumentNullException.ThrowIfNull(mapper);
        return IsFailure() ? Result.Err<T, EOut>(mapper(_error!)) : Result.Ok<T, EOut>(_value!);
    }

    /// <summary>Chains a Result-returning continuation. Callback exceptions are not captured.</summary>
    public Result<TOut, E> Then<TOut>(Func<T, Result<TOut, E>> continuation)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        return IsSuccess() ? continuation(_value!) : Result.Err<TOut, E>(_error!);
    }

    /// <summary>Chains a raw continuation with an explicit exception-capture policy.</summary>
    public Result<TOut, E> Then<TOut>(
        Func<T, TOut> continuation,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(errorMapper);
        if (IsFailure()) return Result.Err<TOut, E>(_error!);

        try
        {
            return Result.Ok<TOut, E>(continuation(_value!));
        }
        catch (Exception exception) when (filter(exception))
        {
            return Result.Err<TOut, E>(errorMapper(exception));
        }
    }

    /// <summary>Runs a raw continuation and maps its success to Unit.</summary>
    public Result<Unit, E> Then(
        Action<T> continuation,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        return Then(
            value => { continuation(value); return new Unit(); },
            filter,
            errorMapper);
    }

    /// <summary>Recovers from a failure with another Result. Callback exceptions are not captured.</summary>
    public Result<T, E> OrElse(Func<E, Result<T, E>> continuation)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        return IsFailure() ? continuation(_error!) : this;
    }

    /// <summary>Runs a success-side effect. Callback exceptions are not captured.</summary>
    public Result<T, E> Do(Action<T> sideEffect)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        if (IsSuccess()) sideEffect(_value!);
        return this;
    }

    /// <summary>Runs a success-side effect with an explicit exception-capture policy.</summary>
    public Result<T, E> Do(
        Action<T> sideEffect,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(errorMapper);
        if (IsFailure()) return this;

        try
        {
            sideEffect(_value!);
            return this;
        }
        catch (Exception exception) when (filter(exception))
        {
            return Result.Err<T, E>(errorMapper(exception));
        }
    }

    /// <summary>Runs a failure-side effect. Callback exceptions are not captured.</summary>
    public Result<T, E> DoFailure(Action<E> sideEffect)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        if (IsFailure()) sideEffect(_error!);
        return this;
    }

    /// <summary>Requires a Result-returning assertion to succeed.</summary>
    public Result<T, E> Assert(Func<T, Result<bool, E>> assertion, Func<T, E> failure)
    {
        ArgumentNullException.ThrowIfNull(assertion);
        ArgumentNullException.ThrowIfNull(failure);
        if (IsFailure()) return this;
        var current = this;
        var value = _value!;
        var checkedResult = assertion(value);
        return checkedResult.Match(
            passed => passed ? current : Result.Err<T, E>(failure(value)),
            error => Result.Err<T, E>(error));
    }

    /// <summary>Requires a raw assertion to succeed with an explicit exception-capture policy.</summary>
    public Result<T, E> Assert(
        Func<T, bool> assertion,
        Func<T, E> failure,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(assertion);
        ArgumentNullException.ThrowIfNull(failure);
        var current = this;
        var value = _value!;
        return Then(input => assertion(input), filter, errorMapper)
            .Then(passed => passed ? current : Result.Err<T, E>(failure(value)));
    }

    /// <summary>Branches to one of two Result-returning continuations.</summary>
    public Result<TOut, E> If<TOut>(
        Func<T, Result<bool, E>> predicate,
        Func<T, Result<TOut, E>> then,
        Func<T, Result<TOut, E>> otherwise)
    {
        ArgumentNullException.ThrowIfNull(predicate);
        ArgumentNullException.ThrowIfNull(then);
        ArgumentNullException.ThrowIfNull(otherwise);
        if (IsFailure()) return Result.Err<TOut, E>(_error!);
        var value = _value!;
        return predicate(value).Then(passed => passed ? then(value) : otherwise(value));
    }

    /// <summary>Exhaustively maps either variant.</summary>
    public TOut Match<TOut>(Func<T, TOut> success, Func<E, TOut> failure)
    {
        ArgumentNullException.ThrowIfNull(success);
        ArgumentNullException.ThrowIfNull(failure);
        EnsureInitialized();
        return _state == SuccessState ? success(_value!) : failure(_error!);
    }

    /// <summary>Exhaustively observes either variant.</summary>
    public void Match(Action<T> success, Action<E> failure)
    {
        ArgumentNullException.ThrowIfNull(success);
        ArgumentNullException.ThrowIfNull(failure);
        EnsureInitialized();
        if (_state == SuccessState) success(_value!); else failure(_error!);
    }

    /// <summary>Gets the success value or throws <see cref="UnwrapException"/>.</summary>
    public T Get()
    {
        EnsureInitialized();
        if (_state == FailureState) throw new UnwrapException("Success", _error);
        return _value!;
    }

    /// <summary>Gets the failure value or throws <see cref="UnwrapException"/>.</summary>
    public E GetFailure()
    {
        EnsureInitialized();
        if (_state == SuccessState) throw new UnwrapException("Failure", _value);
        return _error!;
    }

    /// <summary>Gets the success value or returns a fallback.</summary>
    public T GetOr(T fallback) => IsSuccess() ? _value! : fallback;

    /// <summary>Gets the success value or computes a fallback.</summary>
    public T GetOr(Func<E, T> fallback)
    {
        ArgumentNullException.ThrowIfNull(fallback);
        return IsSuccess() ? _value! : fallback(_error!);
    }

    /// <summary>Gets the success value, or a default value on failure.</summary>
    [return: MaybeNull]
    public T SuccessOrDefault(T? fallback = default) => IsSuccess() ? _value! : fallback;

    /// <summary>Gets the failure value, or a default value on success.</summary>
    [return: MaybeNull]
    public E FailureOrDefault(E? fallback = default) => IsFailure() ? _error! : fallback;

    /// <summary>Projects the success side to an Option.</summary>
    public Option<T> Ok() => IsSuccess() ? Option.Some(_value!) : Option.None<T>();

    /// <summary>Projects the failure side to an Option.</summary>
    public Option<E> Err() => IsFailure() ? Option.Some(_error!) : Option.None<E>();

    /// <summary>Converts to the explicit C0 wire representation.</summary>
    public ResultSerial<T, E> ToSerial() => IsSuccess()
        ? ResultSerial<T, E>.Ok(_value!)
        : ResultSerial<T, E>.Err(_error!);

    /// <inheritdoc />
    public bool Equals(Result<T, E> other)
    {
        EnsureInitialized();
        other.EnsureInitialized();
        return _state == other._state && (_state == SuccessState
            ? EqualityComparer<T>.Default.Equals(_value, other._value)
            : EqualityComparer<E>.Default.Equals(_error, other._error));
    }

    /// <inheritdoc />
    public override bool Equals(object? obj) => obj is Result<T, E> other && Equals(other);

    /// <inheritdoc />
    public override int GetHashCode()
    {
        EnsureInitialized();
        return HashCode.Combine(_state, _state == SuccessState ? _value : default, _state == FailureState ? _error : default);
    }

    /// <inheritdoc />
    public override string ToString()
    {
        EnsureInitialized();
        return _state == SuccessState ? $"Success({_value})" : $"Failure({_error})";
    }

    /// <summary>Converts a success value to a Result.</summary>
    public static implicit operator Result<T, E>(T value) => Result.Ok<T, E>(value);

    /// <summary>Converts a failure value to a Result.</summary>
    public static implicit operator Result<T, E>(E error) => Result.Err<T, E>(error);

    /// <summary>Determines whether two Results are equal.</summary>
    public static bool operator ==(Result<T, E> left, Result<T, E> right) => left.Equals(right);

    /// <summary>Determines whether two Results are unequal.</summary>
    public static bool operator !=(Result<T, E> left, Result<T, E> right) => !left.Equals(right);

    private void EnsureInitialized()
    {
        if (_state is not SuccessState and not FailureState) throw new InvalidResultException();
    }
}
