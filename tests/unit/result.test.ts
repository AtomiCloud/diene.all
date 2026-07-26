import { describe, it } from 'bun:test';
import should from 'should';
import { UnwrapError } from '../../src/lib/error.js';
import { Err, KResult, Ok, Res, type Result } from '../../src/lib/result.js';

describe('Result construction and serialization', () => {
  it('should construct Ok and Err values from immediate and promised payloads', async () => {
    // Arrange
    const promisedValue = Promise.resolve(7);
    const promisedError = Promise.resolve('boom');

    // Act
    const ok = Ok<number, string>(promisedValue);
    const err = Err<number, string>(promisedError);

    // Assert
    should(ok).be.instanceof(KResult);
    should(await ok.isOk()).be.true();
    should(await ok.isErr()).be.false();
    should(await ok.unwrap()).equal(7);
    should(await err.isErr()).be.true();
    should(await err.isOk()).be.false();
    should(await err.unwrapErr()).equal('boom');
  });

  it('should round-trip both ResultSerial variants through JSON', async () => {
    // Arrange
    const okWire = JSON.parse(JSON.stringify(await Ok<number, string>(11).serial())) as ['ok', number];
    const errWire = JSON.parse(JSON.stringify(await Err<number, string>('bad').serial())) as ['err', string];

    // Act
    const ok = Res.fromSerial<number, string>(Promise.resolve(okWire));
    const err = Res.fromSerial<number, string>(errWire);

    // Assert
    should(await ok.unwrap()).equal(11);
    should(await err.unwrapErr()).equal('bad');
  });

  it('should flatten promised Results through fromAsync and async', async () => {
    // Arrange
    const promisedOk = Promise.resolve(Ok<number, string>(3));
    const promisedErr = Promise.resolve(Err<number, string>('no'));

    // Act
    const ok = Res.fromAsync(promisedOk);
    const err = Res.fromAsync(promisedErr);
    const asyncResult = Res.async(async () => Ok<number, string>(9));

    // Assert
    should(await ok.unwrap()).equal(3);
    should(await err.unwrapErr()).equal('no');
    should(await asyncResult.unwrap()).equal(9);
  });

  it('should collect all Ok payloads and collect every Err payload', async () => {
    // Arrange
    const allOk = [Ok<number, string>(1), Ok<string, string>('two')] as const;
    const mixed = [Ok<number, string>(1), Err<string, string>('first'), Err<boolean, string>('second')] as const;

    // Act
    const okResult = Res.all(...allOk);
    const errResult = Res.all(...mixed);

    // Assert
    should(await okResult.unwrap()).eql([1, 'two']);
    should(await errResult.unwrapErr()).eql(['first', 'second']);
  });
});

describe('Result transforms', () => {
  it('should map only Ok and mapErr only Err with async-aware mappers', async () => {
    // Arrange
    const ok = Ok<number, string>(2);
    const err = Err<number, string>('bad');

    // Act
    const mappedOk = ok.map(async value => value * 10);
    const untouchedErr = err.map(value => value * 10);
    const untouchedOk = ok.mapErr(error => `${error}!`);
    const mappedErr = err.mapErr(async error => `${error}!`);

    // Assert
    should(await mappedOk.unwrap()).equal(20);
    should(await untouchedErr.unwrapErr()).equal('bad');
    should(await untouchedOk.unwrap()).equal(2);
    should(await mappedErr.unwrapErr()).equal('bad!');
  });

  it('should chain Ok values and short-circuit Err values', async () => {
    // Arrange
    const ok = Ok<number, string>(4);
    const err = Err<number, string>('stop');

    // Act
    const chainedOk = ok.andThen(async value => Ok<string, string>(`v:${value}`));
    const chainedToErr = ok.andThen(value => Err<string, string>(`e:${value}`));
    const chainedErr = err.andThen(value => Ok<string, string>(`v:${value}`));

    // Assert
    should(await chainedOk.unwrap()).equal('v:4');
    should(await chainedToErr.unwrapErr()).equal('e:4');
    should(await chainedErr.unwrapErr()).equal('stop');
  });

  it('should match both variants and expose their native payloads', async () => {
    // Arrange
    const ok = Ok<number, string>(5);
    const err = Err<number, string>('x');
    const arms = { ok: async (value: number) => `ok:${value}`, err: async (error: string) => `err:${error}` };

    // Act
    const okMatch = ok.match(arms);
    const errMatch = err.match(arms);

    // Assert
    should(await okMatch).equal('ok:5');
    should(await errMatch).equal('err:x');
    should(await ok.native()).equal(5);
    should(await err.native()).equal('x');
  });
});

describe('Result extraction and projection', () => {
  it('should throw UnwrapError only for explicit wrong-variant unwraps', async () => {
    // Arrange
    const ok = Ok<number, string>(8);
    const err = Err<number, string>('why');

    // Act
    const unwrapErrFromOk = (await ok.unwrapErr().catch(error => error as UnwrapError)) as UnwrapError;
    const unwrapOkFromErr = (await err.unwrap().catch(error => error as UnwrapError)) as UnwrapError;

    // Assert
    should(unwrapErrFromOk).be.instanceof(UnwrapError);
    should(unwrapErrFromOk.type).equal('Expected Err got Ok');
    should(unwrapErrFromOk.monadType).equal('result');
    should(unwrapOkFromErr).be.instanceof(UnwrapError);
    should(unwrapOkFromErr.type).equal('Expected Ok got Error');
    should(unwrapOkFromErr.monadType).equal('result');
  });

  it('should return immediate, promised, sync-deferred, and async-deferred fallbacks', async () => {
    // Arrange
    const ok = Ok<number, string>(1);
    const err = Err<number, string>('four');

    // Act / Assert
    should(await ok.unwrapOr(99)).equal(1);
    should(await err.unwrapOr(99)).equal(99);
    should(await err.unwrapOr(Promise.resolve(88))).equal(88);
    should(await err.unwrapOr(error => error.length)).equal(4);
    should(await err.unwrapOr(async error => error.length + 1)).equal(5);
  });

  it('should project each channel into Option', async () => {
    // Arrange
    const ok = Ok<number, string>(2);
    const err = Err<number, string>('z');

    // Act
    const okSome = ok.ok();
    const okNone = err.ok();
    const errNone = ok.err();
    const errSome = err.err();

    // Assert
    should(await okSome.unwrap()).equal(2);
    should(await okNone.isNone()).be.true();
    should(await errNone.isNone()).be.true();
    should(await errSome.unwrap()).equal('z');
  });
});

describe('Result side effects', () => {
  it('should run sync and async effects only for Ok while preserving the Result', async () => {
    // Arrange
    const seen: number[] = [];
    const ok = Ok<number, string>(6);
    const err = Err<number, string>('skip');

    // Act
    const afterSync = ok.run(value => {
      seen.push(value);
    });
    const afterAsync = afterSync.run(async value => {
      seen.push(value + 1);
    });
    const afterErr = err.run(value => {
      seen.push(value);
    });

    // Assert
    should(await afterAsync.unwrap()).equal(6);
    should(await afterErr.unwrapErr()).equal('skip');
    should(seen).eql([6, 7]);
  });

  it('should preserve successful exec values and normalize every thrown shape', async () => {
    // Arrange
    const ok = Ok<number, string>(7);

    // Act
    const success = ok.exec(async () => undefined);
    const fromError = ok.exec(() => {
      throw new Error('error-shape');
    });
    const fromString = ok.exec(() => {
      throw 'string-shape';
    });
    const fromObject = ok.exec(() => {
      throw { shape: 'object' };
    });

    // Assert
    should(await success.unwrap()).equal(7);
    should((await fromError.unwrapErr()).message).equal('error-shape');
    should((await fromString.unwrapErr()).message).equal('string-shape');
    should((await fromObject.unwrapErr()).message).equal('{"shape":"object"}');
  });

  it('should map pre-existing Err values through the default and custom exec mappers', async () => {
    // Arrange
    const nativeError = new Error('native');
    const errorErr = Err<number, Error>(nativeError);
    const objectErr = Err<number, { code: number }>({ code: 4 });
    const stringErr = Err<number, string>('raw');

    // Act
    const preserved = errorErr.exec(() => undefined);
    const normalized = objectErr.exec(() => undefined);
    const custom = stringErr.exec(
      () => undefined,
      async error => new Error(`mapped:${error}`),
    );

    // Assert
    should(await preserved.unwrapErr()).equal(nativeError);
    should((await normalized.unwrapErr()).message).equal('{"code":4}');
    should((await custom.unwrapErr()).message).equal('mapped:raw');
  });
});

describe('Result type surface', () => {
  it('should expose the interface separately from its concrete implementation', async () => {
    // Arrange
    const value: Result<number, string> = Ok<number, string>(10);

    // Act
    const concrete = value as KResult<number, string>;

    // Assert
    should(concrete).be.instanceof(KResult);
    should(await concrete.unwrap()).equal(10);
  });
});
