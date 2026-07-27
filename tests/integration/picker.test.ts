import { afterAll, afterEach, beforeAll, describe, it } from 'bun:test';
import should from 'should';
import { intConfig } from './fixtures/config';
import type { PickerConfig } from '../../src/config';

// Integration: the picker's browser transport against a Doc B fixture. The
// allowlist is BAKED (config-derived, never doc-sourced), so a doc served from
// an off-allowlist host must be refused before any request goes out.

let docBHost: ReturnType<typeof Bun.serve>;
let picker: PickerConfig;
const realFetch = globalThis.fetch;

const DOC_B = {
  version: 1,
  platform: 'diene',
  env: 'lapras',
  landscapes: [
    { name: 'lapras', displayName: 'Lapras', metadata: { region: 'ap-southeast-1' } },
    { name: 'pichu', displayName: 'Pichu', metadata: { region: 'ap-southeast-1' } },
  ],
};

beforeAll(async () => {
  docBHost = Bun.serve({
    port: 0,
    fetch: request => {
      const url = new URL(request.url);
      if (url.pathname === '/malformed') return Response.json({ version: 1 });
      if (url.pathname === '/broken') return new Response('boom', { status: 500 });
      return Response.json(DOC_B);
    },
  });
  const config = await intConfig('base');
  // The shipped config's docBUrl sits on `edge.atomi.cloud`, which its own
  // `allowedSuffixes` (`.cluster.atomi.cloud`) does not cover — the allowlist
  // would refuse it. These specs prove the mechanism against an allowlisted doc
  // URL; the config mismatch itself is reported to the node owner.
  picker = { ...config.get('picker'), docBUrl: 'https://docs.lapras.cluster.atomi.cloud/doc-b.json' };
});

afterAll(() => {
  docBHost.stop(true);
  globalThis.fetch = realFetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

/**
 * Route every request to the local Doc B fixture while keeping the URL the
 * adapter computed, so the allowlist decision under test is the real one.
 */
const routeToFixture = (path = '/doc-b.json'): { readonly seen: string[] } => {
  const seen: string[] = [];
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const requested = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    seen.push(requested);
    return realFetch(`http://127.0.0.1:${docBHost.port}${path}`, init);
  }) as typeof fetch;
  return { seen };
};

describe('fetchDocB', () => {
  it('should fetch and parse Doc B from an allowlisted host', async () => {
    // Arrange
    const { fetchDocB } = await import('../../src/adapters/picker/client');
    const { seen } = routeToFixture();

    // Act
    const doc = await fetchDocB(picker);

    // Assert — names and metadata only; the doc carries no addresses.
    should(doc.landscapes.map(l => l.name)).deepEqual(['lapras', 'pichu']);
    should(seen[0]).containEql('.cluster.atomi.cloud');
  });

  it('should refuse a Doc B URL outside the baked suffix allowlist before requesting it', async () => {
    // Arrange — a doc URL on an attacker-controlled host.
    const { fetchDocB } = await import('../../src/adapters/picker/client');
    const { seen } = routeToFixture();
    const hostile: PickerConfig = { ...picker, docBUrl: 'https://cluster.atomi.cloud.evil.test/doc-b.json' };

    // Act
    const outcome = await fetchDocB(hostile).then(
      () => 'fetched',
      (error: Error) => error.message,
    );

    // Assert — rejected by the allowlist, and no request left the process.
    should(outcome).containEql('rejected by allowlist');
    should(seen).be.empty();
  });

  it('should reject a malformed Doc B rather than handing partial data onward', async () => {
    // Arrange
    const { fetchDocB } = await import('../../src/adapters/picker/client');
    routeToFixture('/malformed');

    // Act
    const outcome = await fetchDocB(picker).then(
      () => 'fetched',
      (error: Error) => error.message,
    );

    // Assert
    should(outcome).containEql('malformed');
  });

  it.each([
    { label: 'a request that timed out', thrown: new DOMException('aborted', 'TimeoutError'), kind: 'timeout' },
    {
      label: 'a host that refused the connection',
      thrown: new TypeError('connect ECONNREFUSED'),
      kind: 'connect-failure',
    },
  ])('should classify $label as $kind rather than a generic error', async ({ thrown, kind }) => {
    // Arrange — the transport distinguishes a slow landscape from an absent one,
    // which is what the picker's per-landscape ping status renders.
    const { fetchDocB } = await import('../../src/adapters/picker/client');
    globalThis.fetch = (() => Promise.reject(thrown)) as unknown as typeof fetch;

    // Act
    const outcome = await fetchDocB(picker).then(
      () => 'fetched',
      (error: Error) => error.message,
    );

    // Assert
    should(outcome).equal(`Doc B fetch failed: ${kind}`);
  });

  it('should surface a transport failure as a fetch failure', async () => {
    // Arrange
    const { fetchDocB } = await import('../../src/adapters/picker/client');
    routeToFixture('/broken');

    // Act
    const outcome = await fetchDocB(picker).then(
      () => 'fetched',
      (error: Error) => error.message,
    );

    // Assert
    should(outcome).containEql('fetch failed');
  });
});

describe('pingAll', () => {
  it('should ping every Doc B landscape at its convention-derived URL', async () => {
    // Arrange
    const { pingAll } = await import('../../src/adapters/picker/client');
    const { seen } = routeToFixture();

    // Act
    const results = await pingAll(DOC_B, picker);

    // Assert — one derived ping.<landscape>.<root> URL per landscape.
    should(results.map(r => r.landscape).sort()).deepEqual(['lapras', 'pichu']);
    should(seen.every(url => url.startsWith('https://ping.'))).be.true();
    should(results.every(r => r.reachable)).be.true();
  });
});

describe('confirmHome', () => {
  it('should wrap a reachable pick into the auth-engine handoff object', async () => {
    // Arrange
    const { confirmHome } = await import('../../src/adapters/picker/client');
    const pings = [
      { landscape: 'lapras', url: 'https://ping.lapras.cluster.atomi.cloud/', reachable: true, latencyMs: 12 },
      { landscape: 'pichu', url: 'https://ping.pichu.cluster.atomi.cloud/', reachable: false, latencyMs: 0 },
    ];

    // Act
    const handoff = await confirmHome(pings, 'lapras');

    // Assert — discovery hands off the assignment; it never writes the home claim.
    should(handoff.kind).equal('home-assignment');
    should(handoff.landscape).equal('lapras');
  });

  it('should refuse a pick that never answered its ping', async () => {
    // Arrange
    const { confirmHome } = await import('../../src/adapters/picker/client');
    const pings = [
      { landscape: 'pichu', url: 'https://ping.pichu.cluster.atomi.cloud/', reachable: false, latencyMs: 0 },
    ];

    // Act
    const outcome = await confirmHome(pings, 'pichu').then(
      () => 'accepted',
      (error: Error) => error.message,
    );

    // Assert
    should(outcome).containEql('home pick failed');
  });
});
