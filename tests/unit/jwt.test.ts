import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { claim, decodeToken, hasRegistrationClaim, isExpired, registrationClaimKey } from '../../src/lib/jwt';
import { buildUnsignedJwt } from '../../src/test-helper/builders';
import { authProblems } from './support';

describe('JWT utilities', () => {
  it('decodes arbitrary claims and reads a typed claim, with an absent claim as Ok(undefined)', async () => {
    // Arrange
    const token = buildUnsignedJwt({ sub: 'user-1', count: 3 });

    // Act
    const decoded = await decodeToken(token).unwrap();
    const count = await claim<number>(token, 'count').unwrap();
    const missing = await claim(token, 'missing').unwrap();

    // Assert
    should(decoded).match({ sub: 'user-1', count: 3 });
    should(count).equal(3);
    should(missing).be.undefined();
  });

  it('returns problem-typed failures for malformed tokens', async () => {
    // Arrange
    const { problems } = authProblems();

    // Act
    const fallback = await decodeToken('not-a-token').unwrapErr();
    const registered = await decodeToken('not-a-token', problems.Unauthorized).unwrapErr();

    // Assert
    should(fallback.type).equal('about:blank');
    should(fallback.status).equal(problems.Unauthorized.status);
    should(registered.type).equal(problems.Unauthorized.type);
  });

  it('surfaces malformed tokens as explicit typed failures for isExpired, claim, and hasRegistrationClaim', async () => {
    // Arrange
    const now = Temporal.Instant.fromEpochMilliseconds(1_000_000);

    // Act
    const expired = isExpired('broken', { now });
    const claimed = claim('broken', 'sub');
    const registration = hasRegistrationClaim('broken', 'my-platform', 'user-service');

    // Assert
    should(await expired.isErr()).be.true();
    should(await claimed.isErr()).be.true();
    should(await registration.isErr()).be.true();
    should((await expired.unwrapErr()).status).equal(401);
  });

  it('rejects blank claim keys, platforms, and services as explicit typed failures', async () => {
    // Arrange
    const token = buildUnsignedJwt({ sub: 'user-1' });

    // Act
    const blankKey = claim(token, '   ');
    const blankPlatform = registrationClaimKey('', 'user-service');
    const blankService = registrationClaimKey('my-platform', '  ');
    const blankRegistration = hasRegistrationClaim(token, '  ', 'user-service');

    // Assert
    should(await blankKey.isErr()).be.true();
    should(await blankPlatform.isErr()).be.true();
    should(await blankService.isErr()).be.true();
    should(await blankRegistration.isErr()).be.true();
    should((await blankPlatform.unwrapErr()).status).equal(400);
  });

  it('uses the exact expiry boundary against an injected instant and treats missing exp as live', async () => {
    // Arrange
    const now = Temporal.Instant.fromEpochMilliseconds(1_000_000);
    const nowSeconds = 1_000;
    const skew = Temporal.Duration.from({ seconds: 30 });
    const future = buildUnsignedJwt({ exp: nowSeconds + 31 });
    const boundary = buildUnsignedJwt({ exp: nowSeconds + 30 });
    const noExpiry = buildUnsignedJwt({ sub: 'user' });

    // Act
    const futureExpired = await isExpired(future, { skew, now }).unwrap();
    const boundaryExpired = await isExpired(boundary, { skew, now }).unwrap();
    const noExpiryExpired = await isExpired(noExpiry, { skew, now }).unwrap();

    // Assert
    should(futureExpired).be.false();
    should(boundaryExpired).be.true();
    should(noExpiryExpired).be.false();
  });

  it('returns typed failures for invalid NumericDate and clock/skew inputs', async () => {
    // Arrange
    const now = Temporal.Instant.fromEpochMilliseconds(1_000_000);
    const impossibleExpiry = buildUnsignedJwt({ exp: 1e100 });
    const minimumExpiry = buildUnsignedJwt({ exp: -8_640_000_000_000 });
    const validToken = buildUnsignedJwt({ exp: 2_000 });

    // Act
    const invalidExpiry = await isExpired(impossibleExpiry, { now }).serial();
    const missingClock = await isExpired(validToken, {} as never).serial();
    const negativeSkew = await isExpired(validToken, {
      now,
      skew: Temporal.Duration.from({ seconds: -1 }),
    }).serial();
    const calendarSkew = await isExpired(validToken, {
      now,
      skew: Temporal.Duration.from({ months: 1 }),
    }).serial();
    const underflow = await isExpired(minimumExpiry, { now }).serial();

    // Assert
    should(invalidExpiry[0]).equal('err');
    should(missingClock[0]).equal('err');
    should(negativeSkew[0]).equal('err');
    should(calendarSkew[0]).equal('err');
    should(underflow[0]).equal('err');
  });

  it('requires the exact string registration claim', async () => {
    // Arrange
    const present = buildUnsignedJwt({ my_platform_user_service: 'true' });
    const wrongType = buildUnsignedJwt({ my_platform_user_service: true });

    // Act
    const key = await registrationClaimKey('My-Platform', 'User-Service').unwrap();
    const hasPresent = await hasRegistrationClaim(present, 'my-platform', 'user-service').unwrap();
    const hasWrongType = await hasRegistrationClaim(wrongType, 'my-platform', 'user-service').unwrap();

    // Assert
    should(key).equal('my_platform_user_service');
    should(hasPresent).be.true();
    should(hasWrongType).be.false();
  });
});
