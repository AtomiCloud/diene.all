import { describe, it } from 'bun:test';
import { dirname, resolve } from 'node:path';
import should from 'should';

const repoRoot = resolve(import.meta.dir, '../..');
const requiredDomainFiles = [
  'docs/domain/README.md',
  'docs/domain/wire-protocol.md',
  'docs/domain/provider-adapters.md',
  'docs/domain/registration-and-delivery.md',
  'docs/domain/tenancy-and-management.md',
  'docs/domain/storage-and-retention.md',
  'docs/domain/operations.md',
  'docs/domain/forbidden-regressions.md',
] as const;

const readRepoFile = async (path: string): Promise<string> => Bun.file(resolve(repoRoot, path)).text();
const implementationGlobs = [
  'src/**/*.ts',
  'infra/root_chart/**/*',
  'infra/primordial_chart/**/*',
  'infra/Dockerfile',
  'infra/kargo/**/*',
  'scripts/**/*',
  '.github/workflows/**/*',
  'package.json',
  'Taskfile.yaml',
] as const;
const forbiddenPatterns = [
  { name: 'Cloudflare runtime', pattern: /\bcloudflare\b/i },
  { name: 'Wrangler release', pattern: /\bwrangler\b/i },
  { name: 'workers intake hostname', pattern: /workers\.atomi\.cloud/i },
  { name: 'child CloudflareDeploy', pattern: /CloudflareDeploy/ },
  { name: 'Worker KV', pattern: /worker[\s_-]*kv/i },
  { name: 'buffer Worker', pattern: /buffer[\s_-]*worker/i },
  { name: 'landscape stamp', pattern: /landscape[\s_-]*stamp/i },
  { name: 'exactly-one owner', pattern: /exactly[\s_-]*one[\s_-]*owner/i },
  { name: 'logical copy', pattern: /logical[\s_-]*cop(?:y|ies)/i },
  { name: 'sibling failover', pattern: /sibling[\s_-]*failover/i },
] as const;

describe('Mercury documentation and design absence', () => {
  it('keeps every authoritative domain page concise and indexed', async () => {
    // Arrange
    const expectedMaximumLines = 300;
    const index = await readRepoFile('docs/domain/README.md');

    // Act
    const pages = await Promise.all(
      requiredDomainFiles.map(async path => ({ path, content: await readRepoFile(path) })),
    );

    // Assert
    for (const page of pages) {
      should(page.content.trim().length > 0).be.true();
      should(page.content.split('\n').length <= expectedMaximumLines).be.true();
      if (page.path !== 'docs/domain/README.md') {
        should(index.includes(page.path.replace('docs/domain/', ''))).be.true();
      }
    }
  });

  it('documents the governing delivery and management invariants', async () => {
    // Arrange
    const requiredStatements: Readonly<Record<string, readonly RegExp[]>> = {
      'docs/domain/wire-protocol.md': [
        /application\/vnd\.atomi\.webhook\.v1\+json/,
        /at-least-once and unordered/i,
        /constant time/i,
        /every consumer must/i,
      ],
      'docs/domain/provider-adapters.md': [
        /stripe/i,
        /airwallex/i,
        /apple-app-store/i,
        /google-play/i,
        /telegram/i,
        /discord/i,
        /logto/i,
        /dual-live/i,
      ],
      'docs/domain/registration-and-delivery.md': [/fan-to-all/i, /locality is address resolution/i, /idempotency/i],
      'docs/domain/tenancy-and-management.md': [
        /immutable home/i,
        /T3 never receives per-landscape Upstash write credentials/i,
        /Mercury alone/i,
        /D7/i,
        /D11/i,
        /D21/i,
      ],
      'docs/domain/storage-and-retention.md': [
        /failure-atomic acceptance/i,
        /generation swaps/i,
        /archive-before-delete/i,
      ],
      'docs/domain/operations.md': [/Apple backfill/i, /31 days/i, /Route 53/i, /console fan-in/i],
    };

    // Act
    const documents = await Promise.all(
      Object.keys(requiredStatements).map(async path => ({ path, content: await readRepoFile(path) })),
    );

    // Assert
    for (const document of documents) {
      const patterns = requiredStatements[document.path] ?? [];
      for (const pattern of patterns) {
        should(pattern.test(document.content)).be.true(
          `${document.path} must contain authoritative statement matching ${pattern}`,
        );
      }
    }
  });

  it('keeps local documentation links resolvable', async () => {
    // Arrange
    const documentationFiles = ['README.md', 'tests/sit/README.md', ...requiredDomainFiles];
    const failures: string[] = [];

    // Act
    for (const path of documentationFiles) {
      const content = await readRepoFile(path);
      const linkPattern = /\[[^\]]+\]\(([^)]+)\)/g;
      for (const match of content.matchAll(linkPattern)) {
        const rawTarget = match[1];
        if (rawTarget === undefined || rawTarget.startsWith('#') || /^[a-z]+:/i.test(rawTarget)) {
          continue;
        }
        const target = rawTarget.split('#')[0];
        if (target === undefined || target.length === 0) {
          continue;
        }
        const absoluteTarget = resolve(repoRoot, dirname(path), target);
        if (!(await Bun.file(absoluteTarget).exists())) {
          failures.push(`${path} -> ${rawTarget}`);
        }
      }
    }

    // Assert
    should(failures).deepEqual([]);
  });

  it('enumerates every forbidden Cloudflare, election, stamping, and failover artifact', async () => {
    // Arrange
    const expectedTerms = [
      'cloudflare worker',
      'd1',
      'worker kv',
      'cloudflare secret bindings',
      'wrangler',
      'workers.atomi.cloud',
      'cloudflaredeploy',
      'orange/proxied webhook route',
      'buffer worker',
      'logical-copy',
      'exactly-one-owner',
      'landscape stamping',
      'owner election',
      'sibling',
      'fallback',
      'cross-landscape event sequencer',
      't3',
      'request `host`',
      'delete-before-archive',
    ];

    // Act
    const actual = (await readRepoFile('docs/domain/forbidden-regressions.md')).toLowerCase();

    // Assert
    for (const term of expectedTerms) {
      should(actual.includes(term)).be.true(`forbidden-regressions.md must cover ${term}`);
    }
  });

  it('finds no forbidden runtime artifacts in implementation and release surfaces', async () => {
    // Arrange
    const failures: string[] = [];
    const scanned = new Set<string>();

    // Act
    for (const globPattern of implementationGlobs) {
      const glob = new Bun.Glob(globPattern);
      for await (const path of glob.scan({ cwd: repoRoot, onlyFiles: true })) {
        scanned.add(path);
        const content = await readRepoFile(path);
        for (const forbidden of forbiddenPatterns) {
          if (forbidden.pattern.test(content)) {
            failures.push(`${path}: ${forbidden.name}`);
          }
        }
      }
    }

    // Assert
    should(failures).deepEqual([]);
    for (const releaseSurface of [
      'infra/root_chart/Chart.yaml',
      'infra/primordial_chart/Chart.yaml',
      'infra/Dockerfile',
      'infra/kargo/promotion-contract.yaml',
    ]) {
      should(scanned.has(releaseSurface)).be.true(`${releaseSurface} must be included by the absence scan`);
    }
  });

  it('would reject a forbidden artifact in every concrete release surface', () => {
    // Arrange
    const representativePaths = [
      'infra/root_chart/templates/deployment.yaml',
      'infra/primordial_chart/templates/project.yaml',
      'infra/Dockerfile',
      'infra/kargo/promotion-contract.yaml',
    ];

    // Act / Assert
    for (const path of representativePaths) {
      should(implementationGlobs.some(pattern => new Bun.Glob(pattern).match(path))).be.true(
        `${path} must match an absence glob`,
      );
      should(forbiddenPatterns.some(forbidden => forbidden.pattern.test('wrangler deploy'))).be.true(
        `${path} must be subject to forbidden-content detection`,
      );
    }
  });
});
