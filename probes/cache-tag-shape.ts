import { expectGreen, expectRed } from './lib/helpers.ts';

const GATE = 'nix develop .#ci -c ./scripts/validate/workflows.sh cache-tag-shape';
const PRECOMMIT = '.github/workflows/⚡reusable-precommit.yaml';
const DOCKER = '.github/workflows/⚡reusable-docker.yaml';
const GATEKEEPER = '.github/workflows/🛡️merge-gatekeeper.yml';

const CACHED_VENUE = [
  '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache',
  '      - nscloud-cache-size-50gb',
  '      - nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64',
].join('\n');

type Edit = { find: string; replace: string };

// A mutation whose target has drifted out of the file would silently sabotage nothing
// and leave the arm asserting a red the gate never had to produce, so a missing target
// is an error rather than a no-op.
async function rewrite(repo: any, path: string, edits: Edit[]): Promise<void> {
  let source: string = await repo.read(path);
  for (const edit of edits) {
    if (!source.includes(edit.find)) {
      throw new Error(`cache-tag-shape mutation target is missing from ${path}: ${edit.find}`);
    }
    source = source.replaceAll(edit.find, edit.replace);
  }
  await repo.write(path, source);
}

function caught(name: string, description: string, path: string, edits: Edit[]) {
  return {
    name,
    description,
    kind: 'mutation' as const,
    expectedImpact: [],
    async run(repo: any) {
      await rewrite(repo, path, edits);
      await expectRed(repo, GATE, 'cache-tag-shape');
    },
  };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-cache-tag-shape-green',
      description:
        'Every workflow selects one exact S31 venue label; jobs that use the Nix store select a cache-capable Namespace venue and rotate their cache tag with the OS.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, GATE, 'cache-tag-shape');
      },
    },
    caught(
      'mutation-nix-cache-loss-caught',
      'A Nix-store job that drops the -with-cache venue together with both cache metadata labels — the shape that made live run 30670113046 fail — must turn the S31 gate red instead of passing as a deliberate isolation lane.',
      PRECOMMIT,
      [{ find: CACHED_VENUE, replace: '      - nscloud-ubuntu-26.04-amd64-16x32' }],
    ),
    caught(
      'mutation-cache-tag-shape-caught',
      'A 24.04 cache tag paired with the selected 26.04 cache-capable Namespace runner must turn the S31 gate red.',
      PRECOMMIT,
      [
        {
          find: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64',
          replace: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-24.04-amd64',
        },
      ],
    ),
    caught(
      'mutation-cache-tag-on-bare-venue-caught',
      'Changing a cache-eligible job to the bare venue while retaining its cache tag must turn the S31 gate red.',
      PRECOMMIT,
      [
        {
          find: 'nscloud-ubuntu-26.04-amd64-16x32-with-cache',
          replace: 'nscloud-ubuntu-26.04-amd64-16x32',
        },
      ],
    ),
    caught(
      'mutation-non-nix-cache-claim-caught',
      'A job that uses no Nix store must not claim the shared Nix-store cache: stripping the Nix setup action and the nix develop wrapper while keeping the cache labels must turn the S31 gate red.',
      DOCKER,
      [
        { find: '      - uses: AtomiCloud/actions.setup-nix@v3\n', replace: '' },
        { find: 'run: nix develop .#cd -c ./scripts/ci/docker.sh', replace: 'run: ./scripts/ci/docker.sh' },
      ],
    ),
    caught(
      'mutation-stale-cache-exemption-caught',
      'A must-not-share-cache exemption recorded while the job still selects a cache-capable venue is stale and must turn the S31 gate red.',
      PRECOMMIT,
      [
        {
          find: '    steps:',
          replace: '    env:\n      S31_CACHE_EXEMPT_REASON: probe-only stale exemption\n    steps:',
        },
      ],
    ),
    caught(
      'mutation-nix-on-hosted-runner-caught',
      'A must-not-share-cache lane is a bare Namespace venue by ruling, so moving a Nix-store job to a GitHub-hosted runner must turn the S31 gate red even when it records an exemption reason.',
      PRECOMMIT,
      [
        {
          find: `    runs-on:\n${CACHED_VENUE}`,
          replace: [
            '    env:',
            '      S31_CACHE_EXEMPT_REASON: probe-only exemption on a hosted runner',
            '    runs-on: ubuntu-26.04',
          ].join('\n'),
        },
      ],
    ),
    caught(
      'mutation-default-runner-label-caught',
      'A default runner label in place of the exact S31 GitHub-hosted primary must turn the S31 gate red.',
      GATEKEEPER,
      [{ find: 'runs-on: ubuntu-26.04', replace: 'runs-on: ubuntu-latest' }],
    ),
    caught(
      'mutation-unrecorded-fallback-caught',
      'Selecting the 24.04 fallback without env.S31_RUNNER_FALLBACK_REASON must turn the S31 gate red.',
      GATEKEEPER,
      [{ find: 'runs-on: ubuntu-26.04', replace: 'runs-on: ubuntu-24.04' }],
    ),
    caught(
      'mutation-combined-namespace-labels-caught',
      'Combining the 26.04 primary and the 24.04 fallback Namespace venue labels on one job must turn the S31 gate red.',
      PRECOMMIT,
      [
        {
          find: '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache',
          replace:
            '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache\n      - nscloud-ubuntu-24.04-amd64-16x32-with-cache',
        },
      ],
    ),
  ],
};
