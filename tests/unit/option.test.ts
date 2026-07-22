import { describe, it } from 'bun:test';
import should from 'should';
import type { UnwrapError } from '../../src/error.ts';
import { None, Option, Some } from '../../src/option.ts';
import { Result } from '../../src/result.ts';
import type { OptionSerial } from '../../src/wire.ts';

describe('Option constructors', () => {
  it('should build a Some that reports isSome', () => {
    // Act
    const actual = Option.some(3);

    // Assert
    should(actual).be.instanceof(Some);
    should(actual.isSome).be.true();
    should(actual.isNone).be.false();
  });

  it('should build a None that reports isNone', () => {
    // Act
    const actual = Option.none<number>();

    // Assert
    should(actual).be.instanceof(None);
    should(actual.isNone).be.true();
    should(actual.isSome).be.false();
  });

  it.each([
    { label: 'null', input: null, some: false },
    { label: 'undefined', input: undefined, some: false },
    { label: 'a value', input: 0, some: true },
  ])('should map $label through fromNullable', ({ input, some }) => {
    // Act
    const actual = Option.fromNullable<number>(input);

    // Assert
    should(actual.isSome).equal(some);
  });
});

describe('Option transforms', () => {
  it('should map a Some and leave None untouched', () => {
    // Act
    const mappedSome = Option.some(2).map(value => value * 10);
    const mappedNone = Option.none<number>().map(value => value * 10);

    // Assert
    should(mappedSome.unwrap()).equal(20);
    should(mappedNone.isNone).be.true();
  });

  it('should andThen chain on Some and short-circuit on None', () => {
    // Arrange
    const half = (value: number) => Option.some(value / 2);

    // Act
    const chainedSome = Option.some(8).andThen(half);
    const chainedNone = Option.none<number>().andThen(half);

    // Assert
    should(chainedSome.unwrap()).equal(4);
    should(chainedNone.isNone).be.true();
  });

  it('should match both variants into one type', () => {
    // Arrange
    const fold = (option: Option<number>) => option.match({ some: v => `some:${v}`, none: () => 'none' });

    // Act / Assert
    should(fold(Option.some(4))).equal('some:4');
    should(fold(Option.none<number>())).equal('none');
  });
});

describe('Option unwrap family', () => {
  it('should unwrap a Some and throw UnwrapError on a None', () => {
    // Act
    let caught: UnwrapError | undefined;
    try {
      Option.none<number>().unwrap();
    } catch (error) {
      caught = error as UnwrapError;
    }

    // Assert
    should(Option.some(9).unwrap()).equal(9);
    should(caught?.monad).equal('option');
    should(caught?.expected).equal('Some');
    should(caught?.actual).equal('None');
  });

  it('should provide unwrapOr and unwrapOrElse fallbacks', () => {
    // Act / Assert
    should(Option.some(1).unwrapOr(99)).equal(1);
    should(Option.none<number>().unwrapOr(99)).equal(99);
    should(Option.some(1).unwrapOrElse(() => 42)).equal(1);
    should(Option.none<number>().unwrapOrElse(() => 42)).equal(42);
  });
});

describe('Option to Result', () => {
  it('should convert via okOr', () => {
    // Act
    const fromSome = Option.some(5).okOr<string>('missing');
    const fromNone = Option.none<number>().okOr<string>('missing');

    // Assert
    should(fromSome.unwrap()).equal(5);
    should(fromNone.unwrapErr()).equal('missing');
  });

  it('should convert via asResult arms', () => {
    // Arrange
    const arms = {
      some: (value: number) => Result.ok<string, string>(`v:${value}`),
      none: () => Result.err<string, string>('empty'),
    };

    // Act
    const fromSome = Option.some(6).asResult(arms);
    const fromNone = Option.none<number>().asResult(arms);

    // Assert
    should(fromSome.unwrap()).equal('v:6');
    should(fromNone.unwrapErr()).equal('empty');
  });

  it('should return the native representation', () => {
    // Act / Assert
    should(Option.some(7).native()).equal(7);
    should(Option.none<number>().native()).be.undefined();
  });
});

describe('Option serial round-trip', () => {
  it('should encode Some and None as tagged objects', () => {
    // Act / Assert
    should(Option.some(3).serial()).eql({ kind: 'some', value: 3 });
    should(Option.none<number>().serial()).eql({ kind: 'none' });
  });

  it('should apply a custom Some encoder', () => {
    // Act
    const actual = Option.some(4).serial({ some: value => value * 2 });

    // Assert
    should(actual).eql({ kind: 'some', value: 8 });
  });

  it('should reconstruct an equal Some and None', () => {
    // Arrange
    const some = Option.some(21);
    const none = Option.none<number>();

    // Act
    const rebuiltSome = Option.fromSerial<number>(some.serial(), { some: value => value as number });
    const rebuiltNone = Option.fromSerial<number>(none.serial(), { some: value => value as number });

    // Assert
    should(rebuiltSome.unwrap()).equal(21);
    should(rebuiltNone.isNone).be.true();
  });

  it.each([
    { label: 'a non-object wire', wire: 42 },
    { label: 'an unknown kind', wire: { kind: 'maybe' } },
    { label: 'a some missing its value', wire: { kind: 'some' } },
    { label: 'a none carrying a value', wire: { kind: 'none', value: 1 } },
  ])('should throw TypeError for $label', ({ wire }) => {
    // Arrange
    const serial = wire as unknown as OptionSerial;

    // Act
    const actual = () => Option.fromSerial<number>(serial, { some: value => value as number });

    // Assert
    should(actual).throw(TypeError);
  });
});
