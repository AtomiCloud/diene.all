import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import {
  checkHomeLandscape,
  deriveLandscapePingUrl,
  parseLandscapeSelector,
  pickLandscape,
  pingLandscapes,
} from '../../src/lib/onboard/pre-onboarding';
import { FakeClock, sequenceClock } from './support';

const RAW_SELECTOR = {
  platform: 'alcohol',
  tier: 'production',
  landscapes: [
    { name: 'lapras', region: 'ap-southeast-1', metadata: { displayName: 'Singapore' } },
    { name: 'mew', region: 'us-east-1' },
  ],
};

describe('pre-onboarding', () => {
  it('routes a nonblank home claim and otherwise enters the distinct selector phase', async () => {
    // Arrange
    // (claims supplied inline per assertion)

    // Act
    const home = await checkHomeLandscape({ home_landscape: 'mew' }).unwrap();
    const blank = await checkHomeLandscape({ home_landscape: '  ' }).unwrap();
    const absent = await checkHomeLandscape({}).unwrap();

    // Assert
    should(home).deepEqual({ phase: 'home', landscape: 'mew' });
    should(blank).deepEqual({ phase: 'pre-onboarding' });
    should(absent).deepEqual({ phase: 'pre-onboarding' });
  });

  it('returns a typed failure for a malformed home-landscape claim', async () => {
    // Arrange
    const claims = { home_landscape: 42 };

    // Act
    const actual = await checkHomeLandscape(claims).serial();

    // Assert
    should(actual[0]).equal('err');
    if (actual[0] !== 'err') return;
    should(actual[1].status).equal(400);
  });

  it('accepts names and metadata but rejects addresses, issuers, and invalid labels', async () => {
    // Arrange
    const withIssuer = { ...RAW_SELECTOR, issuer: 'https://issuer.invalid' };
    const withAddress = {
      ...RAW_SELECTOR,
      landscapes: [{ ...RAW_SELECTOR.landscapes[0], address: 'https://backend.invalid' }],
    };
    const badLabel = { ...RAW_SELECTOR, platform: 'Not-DNS' };

    // Act
    const accepted = await parseLandscapeSelector(RAW_SELECTOR).unwrap();

    // Assert
    should(accepted).deepEqual(RAW_SELECTOR);
    should(await parseLandscapeSelector(withIssuer).isErr()).be.true();
    should(await parseLandscapeSelector(withAddress).isErr()).be.true();
    should(await parseLandscapeSelector(badLabel).isErr()).be.true();
  });

  it('derives convention URLs from validated coordinates without consulting document addresses', async () => {
    // Arrange
    const coordinate = { module: 'api', service: 'zinc', platform: 'alcohol', landscape: 'lapras' } as const;
    const withPath = {
      module: 'api',
      service: 'zinc',
      platform: 'ALCOHOL',
      landscape: 'lapras',
      path: '/status',
    } as const;

    // Act
    const base = await deriveLandscapePingUrl(coordinate).unwrap();
    const scoped = await deriveLandscapePingUrl(withPath).unwrap();

    // Assert
    should(base).equal('https://api.zinc.alcohol.lapras.cluster.atomi.cloud/');
    should(scoped).equal('https://api.zinc.ALCOHOL.lapras.cluster.atomi.cloud/status');
  });

  it('rejects a malformed ping coordinate segment as a typed failure', async () => {
    // Arrange
    const injected = { module: 'api.evil', service: 'zinc', platform: 'alcohol', landscape: 'lapras' };

    // Act
    const result = deriveLandscapePingUrl(injected);

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).status).equal(400);
  });

  it('pings every landscape and picks the fastest healthy candidate', async () => {
    // Arrange
    const selector = await parseLandscapeSelector(RAW_SELECTOR).unwrap();
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));

    // Act
    const result = await pingLandscapes(
      selector,
      { module: 'api', service: 'zinc' },
      async (_url, landscape) => landscape.name !== 'lapras',
      clock,
    ).unwrap();
    const [lapras, mew] = result;
    if (lapras === undefined || mew === undefined) throw new Error('Expected both selector landscapes to be pinged.');
    const ranked = [
      { ...lapras, healthy: true, latency: Temporal.Duration.from({ milliseconds: 20 }) },
      { ...mew, healthy: true, latency: Temporal.Duration.from({ milliseconds: 5 }) },
    ];

    // Assert
    should(result).have.length(2);
    should(result[0]?.healthy).be.false();
    should(result[1]?.healthy).be.true();
    should(pickLandscape(result)?.name).equal('mew');
    should(pickLandscape(ranked)?.name).equal('mew');
    should(pickLandscape(result.map(item => ({ ...item, healthy: false })))).be.undefined();
  });

  it('measures latency deterministically from the injected clock', async () => {
    // Arrange
    const single = await parseLandscapeSelector({
      platform: 'alcohol',
      tier: 'production',
      landscapes: [{ name: 'mew', region: 'us-east-1' }],
    }).unwrap();
    const start = Temporal.Instant.fromEpochMilliseconds(1_000);
    const clock = sequenceClock([start, start.add({ milliseconds: 7 })]);

    // Act
    const result = await pingLandscapes(single, { module: 'api', service: 'zinc' }, async () => true, clock).unwrap();

    // Assert
    should(Temporal.Duration.compare(result[0]?.latency ?? Temporal.Duration.from({}), { milliseconds: 7 })).equal(0);
  });

  it('safe-parses public selector and ping target values before starting work', async () => {
    // Arrange
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));
    const invalidSelector = { ...RAW_SELECTOR, platform: 'bad.platform' } as never;

    // Act
    const invalidDocument = await pingLandscapes(
      invalidSelector,
      { module: 'api', service: 'zinc' },
      () => true,
      clock,
    ).serial();
    const invalidTarget = await pingLandscapes(
      RAW_SELECTOR,
      { module: 'api', service: 'bad.service' },
      () => true,
      clock,
    ).serial();

    // Assert
    should(invalidDocument[0]).equal('err');
    should(invalidTarget[0]).equal('err');
  });

  it('maps ping transport failures to a Problem', async () => {
    // Arrange
    const selector = await parseLandscapeSelector(RAW_SELECTOR).unwrap();
    const clock = new FakeClock(Temporal.Instant.fromEpochMilliseconds(0));

    // Act
    const problem = await pingLandscapes(
      selector,
      { module: 'api', service: 'zinc' },
      () => {
        throw new Error('offline');
      },
      clock,
    ).unwrapErr();

    // Assert
    should(problem.status).equal(400);
    should(problem.detail).equal('offline');
  });
});
