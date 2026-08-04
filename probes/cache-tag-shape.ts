import { capturedEnvCommand, expectGreen, expectRed } from './lib/helpers.ts';

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
type Stage = { edits: Edit[]; reason: string };

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

// An arm may name the refusal it expects. A mutation that turns the gate red for
// some other reason — broken YAML, a label the mutation did not mean to touch —
// would assert nothing about the mechanism the arm exists to protect, and the two
// classifier arms below are exactly where that confusion is easy to miss.
async function expectRedBecause(repo: any, reason: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(GATE), { timeoutMs: 240000 });
  if (result.exitCode === 0) {
    throw new Error('cache-tag-shape stayed green after sabotage');
  }
  const output = `${result.stderr}\n${result.stdout}`;
  if (!output.includes(reason)) {
    throw new Error(`cache-tag-shape turned red for the wrong reason (expected '${reason}'): ${output.trim()}`);
  }
}

function caught(name: string, description: string, path: string, edits: Edit[], reason?: string) {
  return {
    name,
    description,
    kind: 'mutation' as const,
    expectedImpact: [],
    async run(repo: any) {
      await rewrite(repo, path, edits);
      if (reason === undefined) {
        await expectRed(repo, GATE, 'cache-tag-shape');
      } else {
        await expectRedBecause(repo, reason);
      }
    },
  };
}

// An arm may also be a SEQUENCE of independent sabotages against the same file,
// each with its own required refusal. Two mechanisms folded into one mutated
// script would let a single red satisfy both assertions, so a regression in one
// could hide behind the other; run in sequence, each rewrite has to earn its own
// refusal, and stage N+1 starts from the text stage N left behind.
function caughtSequence(name: string, description: string, path: string, stages: Stage[]) {
  return {
    name,
    description,
    kind: 'mutation' as const,
    expectedImpact: [],
    async run(repo: any) {
      for (const stage of stages) {
        await rewrite(repo, path, stage.edits);
        await expectRedBecause(repo, stage.reason);
      }
    },
  };
}

// The refusal the classifier arms must provoke. It carries the parenthetical of
// the DEFINITE non-Nix message on purpose: the gate's third answer — "cannot be
// read" — opens with the same clause, and a reason that matched both would let an
// unreadable-syntax refusal stand in for the definite one these arms are proving.
const NOT_A_NIX_STORE_USER =
  'claims the shared S31 Nix-store cache but is not a Nix-store user (no Nix setup action and no nix command in its steps)';

// The gate's third answer: the script uses syntax the reader will not guess at,
// so the cache claim is refused without asserting that no Nix runs.
const NOT_CONFIRMABLE = 'is not a Nix-store user that this gate can confirm';

// A `run:` block scalar at the Docker step's indentation.
const runBlock = (...lines: string[]) => ['run: |', ...lines.map(line => `          ${line}`)].join('\n');

// The run: texts the mention sequence walks through, each replacing the last.
const RUN_REAL = 'run: nix develop .#cd -c ./scripts/ci/docker.sh';
const RUN_ECHO = 'run: echo nix develop; ./scripts/ci/docker.sh';
const RUN_ARRAY = runBlock('args=(nix develop)', `printf '%s\\n' "\${args[*]}"`, './scripts/ci/docker.sh');
const RUN_CASE_PATTERN = runBlock('case "$1" in', '  nix-build)', '    ./scripts/ci/docker.sh', '    ;;', 'esac');
const RUN_NIX_VERSION = 'run: nix --version develop; ./scripts/ci/docker.sh';

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
        await rewrite(repo, DOCKER, [
          { find: '      - uses: AtomiCloud/actions.setup-nix@v3\n', replace: '' },
          {
            find: RUN_REAL,
            replace: 'run: FOO=nix nix develop .#cd -c ./scripts/ci/docker.sh',
          },
        ]);
        await expectGreen(repo, GATE, 'cache-tag-shape assignment-prefixed nix invocation');
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
      NOT_A_NIX_STORE_USER,
    ),
    caughtSequence(
      'mutation-textual-nix-mention-cache-claim-caught',
      'A job whose run: script does not demonstrably invoke Nix must not claim the shared Nix-store cache. Four independent shapes, each proved on its own: a harmless `echo nix develop`; a Bash array literal `args=(nix develop)`, whose parenthesis is not a subshell; a `case` branch pattern named `nix-build`, which is matched rather than run; and `nix --version develop`, where the first argument decides what nix does and a supported word later in the tail proves nothing.',
      DOCKER,
      [
        {
          edits: [
            { find: '      - uses: AtomiCloud/actions.setup-nix@v3\n', replace: '' },
            { find: RUN_REAL, replace: RUN_ECHO },
          ],
          reason: NOT_A_NIX_STORE_USER,
        },
        { edits: [{ find: RUN_ECHO, replace: RUN_ARRAY }], reason: NOT_A_NIX_STORE_USER },
        { edits: [{ find: RUN_ARRAY, replace: RUN_CASE_PATTERN }], reason: NOT_A_NIX_STORE_USER },
        // The last stage is refused for the OTHER reason: the gate does not claim
        // that no Nix runs here, only that it cannot confirm that any does.
        { edits: [{ find: RUN_CASE_PATTERN, replace: RUN_NIX_VERSION }], reason: NOT_CONFIRMABLE },
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
