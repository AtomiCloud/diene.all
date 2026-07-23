import { describe, it } from 'bun:test';
import should from 'should';
import { UnwrapError } from '../../src/lib/error.js';
import { KOption, None, Opt, Some, type Option, type OptionSerial } from '../../src/lib/option.js';
import { Err, Ok } from '../../src/lib/result.js';

describe('Option construction and serialization', () => {
  it('should construct Some and None and map nullable native values', async () => {
    // Arrange
    const nativeValues = [0, null, undefined] as const;

    // Act
    const some = Some(3);
    const none = None<number>();
    const mapped = nativeValues.map(value => Opt.fromNative(value));

    // Assert
    should(some).be.instanceof(KOption);
    should(await some.isSome()).be.true();
    should(await some.isNone()).be.false();
    should(await none.isNone()).be.true();
    should(await none.isSome()).be.false();
    should(await mapped[0]?.unwrap()).equal(0);
    should(await mapped[1]?.isNone()).be.true();
    should(await mapped[2]?.isNone()).be.true();
  });

  it('should round-trip both OptionSerial variants through JSON', async () => {
    // Arrange
    const someWire = JSON.parse(JSON.stringify(await Some(12).serial())) as OptionSerial<number>;
    const noneWire = JSON.parse(JSON.stringify(await None<number>().serial())) as OptionSerial<number>;

    // Act
    const some = Opt.fromSerial(Promise.resolve(someWire));
    const none = Opt.fromSerial(noneWire);

    // Assert
    should(await some.unwrap()).equal(12);
    should(await none.isNone()).be.true();
    should(await some.native()).equal(12);
    should(await none.native()).be.null();
  });

  it('should flatten async Options and collect only when every member is Some', async () => {
    // Arrange
    const promisedSome = Promise.resolve(Some(4));
    const promisedNone = Promise.resolve(None<number>());

    // Act
    const some = Opt.fromAsync(promisedSome);
    const none = Opt.fromAsync(promisedNone);
    const asyncOption = Opt.async(async () => Some(8));
    const allSome = Opt.all(Some(1), Some('two'));
    const withNone = Opt.all(Some(1), None<string>());

    // Assert
    should(await some.unwrap()).equal(4);
    should(await none.isNone()).be.true();
    should(await asyncOption.unwrap()).equal(8);
    should(await allSome.unwrap()).eql([1, 'two']);
    should(await withNone.isNone()).be.true();
  });
});

describe('Option transforms', () => {
  it('should map Some values and leave None values untouched', async () => {
    // Arrange
    const some = Some(2);
    const none = None<number>();

    // Act
    const mappedSome = some.map(async value => value * 10);
    const mappedNone = none.map(value => value * 10);

    // Assert
    should(await mappedSome.unwrap()).equal(20);
    should(await mappedNone.isNone()).be.true();
  });

  it('should chain Some values, propagate mapped None, and short-circuit original None', async () => {
    // Arrange
    const some = Some(6);
    const none = None<number>();

    // Act
    const chainedSome = some.andThen(async value => Some(`v:${value}`));
    const chainedToNone = some.andThen(() => None<string>());
    const chainedNone = none.andThen(value => Some(`v:${value}`));

    // Assert
    should(await chainedSome.unwrap()).equal('v:6');
    should(await chainedToNone.isNone()).be.true();
    should(await chainedNone.isNone()).be.true();
  });

  it('should match Some and both deferred and immediate None arms', async () => {
    // Arrange
    const some = Some(5);
    const none = None<number>();

    // Act
    const someMatch = some.match({ some: value => `some:${value}`, none: 'none' });
    const noneImmediate = none.match<string>({ some: value => `some:${value}`, none: Promise.resolve('none') });
    const noneDeferred = none.match<string>({ some: value => `some:${value}`, none: async () => 'deferred' });

    // Assert
    should(await someMatch).equal('some:5');
    should(await noneImmediate).equal('none');
    should(await noneDeferred).equal('deferred');
  });
});

describe('Option extraction and side effects', () => {
  it('should unwrap Some and throw UnwrapError for explicit None unwrap', async () => {
    // Arrange
    const some = Some(9);
    const none = None<number>();

    // Act
    const rejected = (await none.unwrap().catch(error => error as UnwrapError)) as UnwrapError;

    // Assert
    should(await some.unwrap()).equal(9);
    should(rejected).be.instanceof(UnwrapError);
    should(rejected.type).equal('Expected Some got None');
    should(rejected.monadType).equal('option');
  });

  it('should return immediate, promised, sync-deferred, and async-deferred fallbacks', async () => {
    // Arrange
    const some = Some(1);
    const none = None<number>();

    // Act / Assert
    should(await some.unwrapOr(99)).equal(1);
    should(await none.unwrapOr(99)).equal(99);
    should(await none.unwrapOr(Promise.resolve(88))).equal(88);
    should(await none.unwrapOr(() => 77)).equal(77);
    should(await none.unwrapOr(async () => 66)).equal(66);
  });

  it('should run sync and async effects only for Some while preserving the Option', async () => {
    // Arrange
    const seen: number[] = [];
    const some = Some(4);
    const none = None<number>();

    // Act
    const afterSync = some.run(value => {
      seen.push(value);
    });
    const afterAsync = afterSync.run(async value => {
      seen.push(value + 1);
    });
    const afterNone = none.run(value => {
      seen.push(value);
    });

    // Assert
    should(await afterAsync.unwrap()).equal(4);
    should(await afterNone.isNone()).be.true();
    should(seen).eql([4, 5]);
  });
});

describe('Option to Result conversion', () => {
  it('should convert Some and None through asOk and asErr', async () => {
    // Arrange
    const some = Some(5);
    const none = None<number>();

    // Act
    const someAsOk = some.asOk('missing');
    const noneAsOk = none.asOk(Promise.resolve('missing'));
    const someAsErr = some.asErr('fallback');
    const noneAsErr = none.asErr(Promise.resolve('fallback'));

    // Assert
    should(await someAsOk.unwrap()).equal(5);
    should(await noneAsOk.unwrapErr()).equal('missing');
    should(await someAsErr.unwrapErr()).equal(5);
    should(await noneAsErr.unwrap()).equal('fallback');
  });

  it('should map Some and every None arm shape through asResult', async () => {
    // Arrange
    const some = Some(3);
    const none = None<number>();

    // Act
    const fromSome = some.asResult({ some: value => Ok<string, string>(`v:${value}`), none: Err('empty') });
    const fromNoneValue = none.asResult({ some: value => Ok<string, string>(`v:${value}`), none: Err('empty') });
    const fromNoneFunction = none.asResult({
      some: value => Ok<string, string>(`v:${value}`),
      none: async () => Ok<string, string>('fallback'),
    });

    // Assert
    should(await fromSome.unwrap()).equal('v:3');
    should(await fromNoneValue.unwrapErr()).equal('empty');
    should(await fromNoneFunction.unwrap()).equal('fallback');
  });
});

describe('Option type surface', () => {
  it('should expose the interface separately from its concrete implementation', async () => {
    // Arrange
    const value: Option<number> = Some(10);

    // Act
    const concrete = value as KOption<number>;

    // Assert
    should(concrete).be.instanceof(KOption);
    should(await concrete.unwrap()).equal(10);
  });
});
