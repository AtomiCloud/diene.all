import { describe, it } from 'bun:test';
import should from 'should';
import { UnwrapError } from '../../src/error.ts';
import { Err, Ok, Result } from '../../src/result.ts';

describe('Result constructors', () => {
  it('should build an Ok that reports isOk', () => {
    // Arrange
    const value = 7;

    // Act
    const actual = Result.ok<number, string>(value);

    // Assert
    should(actual).be.instanceof(Ok);
    should(actual.isOk).be.true();
    should(actual.isErr).be.false();
  });

  it('should build an Err that reports isErr', () => {
    // Arrange
    const error = 'boom';

    // Act
    const actual = Result.err<string, number>(error);

    // Assert
    should(actual).be.instanceof(Err);
    should(actual.isErr).be.true();
    should(actual.isOk).be.false();
  });
});

describe('Result transforms', () => {
  it('should map the Ok channel and leave Err untouched', () => {
    // Arrange
    const ok = Result.ok<number, string>(2);
    const err = Result.err<string, number>('bad');

    // Act
    const mappedOk = ok.map(value => value * 10);
    const mappedErr = err.map(value => value * 10);

    // Assert
    should(mappedOk.unwrap()).equal(20);
    should(mappedErr.unwrapErr()).equal('bad');
  });

  it('should mapErr the Err channel and leave Ok untouched', () => {
    // Arrange
    const ok = Result.ok<number, string>(2);
    const err = Result.err<string, number>('bad');

    // Act
    const mappedOk = ok.mapErr(error => `${error}!`);
    const mappedErr = err.mapErr(error => `${error}!`);

    // Assert
    should(mappedOk.unwrap()).equal(2);
    should(mappedErr.unwrapErr()).equal('bad!');
  });

  it('should andThen chain on Ok and short-circuit on Err', () => {
    // Arrange
    const ok = Result.ok<number, string>(3);
    const err = Result.err<string, number>('nope');
    const half = (value: number) => Result.ok<number, string>(value / 2);

    // Act
    const chainedOk = ok.andThen(half);
    const chainedErr = err.andThen(half);

    // Assert
    should(chainedOk.unwrap()).equal(1.5);
    should(chainedErr.unwrapErr()).equal('nope');
  });

  it('should match both variants into one type', () => {
    // Arrange
    const ok = Result.ok<number, string>(4);
    const err = Result.err<string, number>('x');
    const fold = (result: typeof ok) => result.match({ ok: v => `ok:${v}`, err: e => `err:${e}` });

    // Act / Assert
    should(fold(ok)).equal('ok:4');
    should(fold(err as unknown as typeof ok)).equal('err:x');
  });
});

describe('Result run and exec', () => {
  it('should run a side effect on Ok and skip it on Err', () => {
    // Arrange
    const seen: number[] = [];
    const ok = Result.ok<number, string>(5);
    const err = Result.err<string, number>('e');

    // Act
    const afterOk = ok.run(value => seen.push(value));
    const afterErr = err.run(value => seen.push(value));

    // Assert
    should(seen).eql([5]);
    should(afterOk.unwrap()).equal(5);
    should(afterErr.unwrapErr()).equal('e');
  });

  it('should leave Ok untouched when exec side effect does not throw', () => {
    // Arrange
    const ok = Result.ok<number, string>(6);

    // Act
    const actual = ok.exec(
      () => undefined,
      () => 'never',
    );

    // Assert
    should(actual.unwrap()).equal(6);
  });

  it('should poison the chain into Err when exec side effect throws', () => {
    // Arrange
    const ok = Result.ok<number, string>(6);

    // Act
    const actual = ok.exec(
      () => {
        throw new Error('kaboom');
      },
      error => `caught:${(error as Error).message}`,
    );

    // Assert
    should(actual.isErr).be.true();
    should(actual.unwrapErr()).equal('caught:kaboom');
  });

  it('should leave an Err untouched under exec', () => {
    // Arrange
    const err = Result.err<string, number>('pre');

    // Act
    const actual = err.exec(
      () => {
        throw new Error('unreached');
      },
      () => 'mapped',
    );

    // Assert
    should(actual.unwrapErr()).equal('pre');
  });
});

describe('Result unwrap family', () => {
  it('should unwrap an Ok value and throw UnwrapError on an Err', () => {
    // Arrange
    const ok = Result.ok<number, string>(9);
    const err = Result.err<string, number>('why');

    // Act / Assert
    should(ok.unwrap()).equal(9);
    should(() => err.unwrap()).throw(UnwrapError);
  });

  it('should carry the offending payload when unwrap rejects an Err', () => {
    // Arrange
    const err = Result.err<string, number>('why');

    // Act
    let caught: UnwrapError | undefined;
    try {
      err.unwrap();
    } catch (error) {
      caught = error as UnwrapError;
    }

    // Assert
    should(caught?.monad).equal('result');
    should(caught?.expected).equal('Ok');
    should(caught?.actual).equal('Err');
    should(caught?.payload).equal('why');
  });

  it('should unwrapErr an Err error and throw UnwrapError on an Ok', () => {
    // Arrange
    const ok = Result.ok<number, string>(9);
    const err = Result.err<string, number>('why');

    // Act
    let caught: UnwrapError | undefined;
    try {
      ok.unwrapErr();
    } catch (error) {
      caught = error as UnwrapError;
    }

    // Assert
    should(err.unwrapErr()).equal('why');
    should(caught?.expected).equal('Err');
    should(caught?.actual).equal('Ok');
    should(caught?.payload).equal(9);
  });

  it('should provide unwrapOr and unwrapOrElse fallbacks', () => {
    // Arrange
    const ok = Result.ok<number, string>(1);
    const err = Result.err<string, number>('len');

    // Act / Assert
    should(ok.unwrapOr(99)).equal(1);
    should(err.unwrapOr(99)).equal(99);
    should(ok.unwrapOrElse(e => e.length)).equal(1);
    should(err.unwrapOrElse(e => e.length)).equal(3);
  });
});

describe('Result projections', () => {
  it('should project ok() and err() into Option', () => {
    // Arrange
    const ok = Result.ok<number, string>(2);
    const err = Result.err<string, number>('z');

    // Act / Assert
    should(ok.ok().isSome).be.true();
    should(ok.err().isNone).be.true();
    should(err.ok().isNone).be.true();
    should(err.err().unwrap()).equal('z');
  });

  it('should return the native payload of whichever variant', () => {
    // Arrange
    const ok = Result.ok<number, string>(3);
    const err = Result.err<string, number>('n');

    // Act / Assert
    should(ok.native()).equal(3);
    should(err.native()).equal('n');
  });
});

describe('Result monad laws', () => {
  const f = (value: number) => Result.ok<number, string>(value + 1);
  const g = (value: number) => Result.ok<number, string>(value * 2);

  it('should satisfy left identity: ok(a).andThen(f) == f(a)', () => {
    // Arrange
    const a = 10;

    // Act / Assert
    should(Result.ok<number, string>(a).andThen(f).unwrap()).equal(f(a).unwrap());
  });

  it('should satisfy right identity: m.andThen(ok) == m', () => {
    // Arrange
    const m = Result.ok<number, string>(10);

    // Act / Assert
    should(m.andThen(value => Result.ok<number, string>(value)).unwrap()).equal(m.unwrap());
  });

  it('should satisfy associativity', () => {
    // Arrange
    const m = Result.ok<number, string>(10);

    // Act
    const left = m.andThen(f).andThen(g);
    const right = m.andThen(value => f(value).andThen(g));

    // Assert
    should(left.unwrap()).equal(right.unwrap());
  });
});
