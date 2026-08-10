import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import type { ResultSerial } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import {
  type AuthState,
  authed,
  createAuthStateCell,
  createSingleFlightCell,
  stateNeedRefresh,
  systemClock,
  type TokenSet,
} from '../../src/lib/retriever';
import { buildUnsignedJwt } from '../../src/test-helper/builders';

describe('retriever state seams', () => {
  it('exposes a production clock and an explicitly mutable auth-state cell', () => {
    // Arrange
    const cell = createAuthStateCell<TokenSet>();
    const state = authed<TokenSet>({ idToken: buildUnsignedJwt({ sub: 'user-1' }), accessTokens: {} });

    // Act
    const now = systemClock.now();
    const beforeWrite = cell.peek();
    cell.write(state);
    const afterWrite = cell.peek();
    cell.clear();
    const afterClear = cell.peek();

    // Assert
    should(now instanceof Temporal.Instant).be.true();
    should(beforeWrite).be.undefined();
    should(afterWrite).equal(state);
    should(afterClear).be.undefined();
  });

  it('settles only the current single flight and supports explicit invalidation', () => {
    // Arrange
    const cell = createSingleFlightCell<TokenSet>();
    const state = authed<TokenSet>({ idToken: buildUnsignedJwt({ sub: 'user-1' }), accessTokens: {} });
    const first: Promise<ResultSerial<AuthState<TokenSet>, Problem>> = Promise.resolve(['ok', state]);
    const replacement: Promise<ResultSerial<AuthState<TokenSet>, Problem>> = Promise.resolve(['ok', state]);

    // Act
    cell.begin(first);
    cell.settle(replacement);
    const afterMismatch = cell.peek();
    cell.settle(first);
    const afterMatch = cell.peek();
    cell.begin(replacement);
    cell.clear();
    const afterClear = cell.peek();

    // Assert
    should(afterMismatch).equal(first);
    should(afterMatch).be.undefined();
    should(afterClear).be.undefined();
  });

  it('detects fresh, expired, and malformed token sets without hiding failures', async () => {
    // Arrange
    const now = Temporal.Instant.fromEpochMilliseconds(1_000_000);
    const future = buildUnsignedJwt({ exp: 1_031 });
    const boundary = buildUnsignedJwt({ exp: 1_030 });

    // Act
    const fresh = await stateNeedRefresh({ idToken: future, accessTokens: {} }, { now }).unwrap();
    const expired = await stateNeedRefresh(
      { idToken: future, accessTokens: { 'alcohol/zinc/api/lapras': boundary } },
      { now },
    ).unwrap();
    const malformed = stateNeedRefresh({ idToken: 'broken', accessTokens: {} }, { now });

    // Assert
    should(fresh).be.false();
    should(expired).be.true();
    should(await malformed.isErr()).be.true();
    should((await malformed.unwrapErr()).status).equal(401);
  });
});
