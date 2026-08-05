import { capturedEnvCommand, expectGreen, expectRed } from './lib/helpers.ts';

const GATE = 'nix develop .#ci -c ./scripts/validate/workflows.sh cache-tag-shape';
const PRECOMMIT = '.github/workflows/⚡reusable-precommit.yaml';
const DOCKER = '.github/workflows/⚡reusable-docker.yaml';
const GATEKEEPER = '.github/workflows/🛡️merge-gatekeeper.yml';
const SHELLS = 'nix/shells.nix';

const CACHED_VENUE = [
  '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache',
  '      - nscloud-cache-size-50gb',
  '      - nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64',
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
// would assert nothing about the mechanism the arm exists to protect.
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

// A green whose SUMMARY LINE is also asserted. A gate that quietly stopped reading
// some of the jobs would still exit 0, so the counts are part of the assertion:
// they are the only evidence in the output that the classification ran at all.
async function expectGreenReporting(repo: any, reason: string): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(GATE), { timeoutMs: 240000 });
  if (result.exitCode !== 0) {
    throw new Error(`cache-tag-shape failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
  const output = `${result.stderr}\n${result.stdout}`;
  if (!output.includes(reason)) {
    throw new Error(`cache-tag-shape went green with the wrong tally (expected '${reason}'): ${output.trim()}`);
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

// The refusal every declared-shell arm must provoke. The rule it protects replaced
// this gate's former shell lexer: rather than deciding, from the text of a script,
// whether it uses the Nix store, the gate requires every run: step to ENTER a shell
// that declares its dependencies. There is then nothing left to infer — which is
// why "cannot be read" is no longer one of the answers.
const NOT_IN_A_DECLARED_SHELL = 'does not enter a declared Nix shell';

// A `run:` block scalar at the Docker step's indentation.
const runBlock = (...lines: string[]) => ['run: |', ...lines.map(line => `          ${line}`)].join('\n');

const RUN_REAL = 'run: nix develop .#cd -c ./scripts/ci/docker.sh';
const RUN_BARE = 'run: ./scripts/ci/docker.sh';
const RUN_UNDECLARED_SHELL = 'run: nix develop .#typo -c ./scripts/ci/docker.sh';
// Enters the shell on the first line, then leaves it on the second. The gate
// anchors its matcher on the whole script rather than on a line, precisely for this.
const RUN_ESCAPES = runBlock('nix develop .#cd -c ./scripts/ci/docker.sh', './scripts/ci/docker.sh');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-cache-tag-shape-green',
      description:
        'Every job either runs its work in a dev shell that declares its dependencies and carries the shared Nix-store cache labels, or is a declared isolation lane, or runs no repository script at all.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, GATE, 'cache-tag-shape');
        // The tally is asserted, not just the exit code: 4 run: steps, 4 cached jobs
        // and 1 script-free GitHub-hosted job is the whole workflow set, so a gate
        // that stopped reading part of it cannot pass this arm.
        await expectGreenReporting(
          repo,
          '5 jobs, 4 run: steps in declared shells (4 cached, 0 isolation lanes, 0 bare Namespace, 1 GitHub-hosted script-free)',
        );
      },
    },
    caughtSequence(
      'mutation-run-step-outside-declared-shell-caught',
      'Every run: step must enter a dev shell that declares its dependencies. Three independent escapes, each proved on its own: running the script bare; entering a shell this repository does not declare; and entering the shell on the first line of a multi-line script, then running a second command outside it.',
      DOCKER,
      [
        { edits: [{ find: RUN_REAL, replace: RUN_BARE }], reason: NOT_IN_A_DECLARED_SHELL },
        { edits: [{ find: RUN_BARE, replace: RUN_UNDECLARED_SHELL }], reason: NOT_IN_A_DECLARED_SHELL },
        { edits: [{ find: RUN_UNDECLARED_SHELL, replace: RUN_ESCAPES }], reason: NOT_IN_A_DECLARED_SHELL },
      ],
    ),
    caught(
      'mutation-local-composite-action-caught',
      'A repository-local composite action can carry run: steps of its own that this gate never reads, so it is a route around the declared-shell rule rather than a use of it, and must turn the gate red.',
      PRECOMMIT,
      [
        {
          find: '      - uses: AtomiCloud/actions.setup-nix@v3',
          replace: '      - uses: ./.github/actions/setup\n      - uses: AtomiCloud/actions.setup-nix@v3',
        },
      ],
      'repository-local composite action',
    ),
    caught(
      'mutation-nix-cache-loss-caught',
      'A job that runs its work in a Nix shell but drops the -with-cache venue together with both cache metadata labels — the shape that made live run 30670113046 fail — must turn the gate red instead of passing as a deliberate isolation lane.',
      PRECOMMIT,
      [{ find: CACHED_VENUE, replace: '      - nscloud-ubuntu-26.04-amd64-16x32' }],
      'bare venue that cannot attach a cache volume',
    ),
    {
      // A positive arm, and the reason the rule is two-sided rather than a blanket
      // ban: the threat model's must-not-share-cache lane has to stay expressible.
      // Without this, a gate that simply refused every bare venue would still pass
      // every other arm in this file.
      name: 'mutation-declared-isolation-lane-stays-legal',
      description:
        'A Nix-store job on the bare Namespace venue that records a non-empty job-level env.NIX_CACHE_EXEMPT_REASON is a deliberate isolation lane and must stay GREEN, so the cache rule refuses accidents without making the isolation lane unexpressible.',
      kind: 'mutation' as const,
      expectedImpact: [],
      async run(repo: any) {
        await rewrite(repo, PRECOMMIT, [
          {
            find: `    runs-on:\n${CACHED_VENUE}`,
            replace: [
              '    env:',
              '      NIX_CACHE_EXEMPT_REASON: probe-only isolation lane',
              '    runs-on:',
              '      - nscloud-ubuntu-26.04-amd64-16x32',
            ].join('\n'),
          },
        ]);
        await expectGreenReporting(
          repo,
          '5 jobs, 4 run: steps in declared shells (3 cached, 1 isolation lanes, 1 bare Namespace, 1 GitHub-hosted script-free)',
        );
      },
    },
    caught(
      'mutation-stale-cache-exemption-caught',
      'An isolation-lane exemption recorded while the job still selects a cache-capable venue is stale and must turn the gate red.',
      PRECOMMIT,
      [
        {
          find: '    steps:',
          replace: '    env:\n      NIX_CACHE_EXEMPT_REASON: probe-only stale exemption\n    steps:',
        },
      ],
      'while selecting a cache-capable',
    ),
    caught(
      'mutation-exemption-on-hosted-runner-caught',
      'A GitHub-hosted runner never attaches a Namespace cache, so an exemption recorded there is a record of nothing and must turn the gate red.',
      GATEKEEPER,
      [
        {
          find: '    runs-on: ubuntu-26.04',
          replace: '    env:\n      NIX_CACHE_EXEMPT_REASON: probe-only bogus exemption\n    runs-on: ubuntu-26.04',
        },
      ],
      'never attaches a Namespace cache',
    ),
    caught(
      'mutation-script-free-job-claims-cache-caught',
      'A job with no run: step and no Nix setup action runs no repository script, so it has no Nix store to share and must not claim the shared cache. This is the third job class, and it is what keeps an action-only GitHub-hosted job legal without letting it take a cache volume.',
      GATEKEEPER,
      [
        {
          find: '    runs-on: ubuntu-26.04',
          replace: `    runs-on:\n${CACHED_VENUE}`,
        },
      ],
      'runs no repository script',
    ),
    caught(
      'mutation-script-job-on-hosted-runner-caught',
      'Every job that runs a repository script runs it in a declared Nix shell and therefore uses the Nix store, so a GitHub-hosted runner is never a legal home for one and must turn the gate red.',
      PRECOMMIT,
      [{ find: `    runs-on:\n${CACHED_VENUE}`, replace: '    runs-on: ubuntu-26.04' }],
      'on a GitHub-hosted runner',
    ),
    caughtSequence(
      'mutation-cache-tag-shape-caught',
      'The shared cache tag is exact and OS-sensitive. Two independent drifts, each proved on its own: reintroducing the organization component the tag deliberately no longer carries, and pairing a 24.04 tag with the selected 26.04 venue instead of rotating it.',
      PRECOMMIT,
      [
        {
          edits: [
            {
              find: 'nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64',
              replace: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64',
            },
          ],
          reason: 'cache tag must be',
        },
        {
          edits: [
            {
              find: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64',
              replace: 'nscloud-cache-tag-nix-store-cache-ubuntu-24.04-amd64',
            },
          ],
          reason: 'cache tag must be',
        },
      ],
    ),
    caught(
      'mutation-missing-cache-size-label-caught',
      'A cache-eligible job carries exactly one Namespace cache-size label; dropping it must turn the gate red.',
      PRECOMMIT,
      [{ find: '      - nscloud-cache-size-50gb\n', replace: '' }],
      'exactly one Namespace cache-size label',
    ),
    caught(
      'mutation-combined-namespace-labels-caught',
      'Combining the 26.04 primary and the 24.04 fallback Namespace venue labels on one job must turn the gate red.',
      PRECOMMIT,
      [
        {
          find: '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache',
          replace:
            '      - nscloud-ubuntu-26.04-amd64-16x32-with-cache\n      - nscloud-ubuntu-24.04-amd64-16x32-with-cache',
        },
      ],
      'exactly one primary or fallback venue label',
    ),
    caught(
      'mutation-default-runner-label-caught',
      'A default runner label in place of the exact GitHub-hosted primary must turn the gate red.',
      GATEKEEPER,
      [{ find: 'runs-on: ubuntu-26.04', replace: 'runs-on: ubuntu-latest' }],
      'unsupported runner labels',
    ),
    caught(
      'mutation-unrecorded-fallback-caught',
      'Selecting the 24.04 fallback without env.NIX_RUNNER_FALLBACK_REASON must turn the gate red.',
      GATEKEEPER,
      [{ find: 'runs-on: ubuntu-26.04', replace: 'runs-on: ubuntu-24.04' }],
      'without env.NIX_RUNNER_FALLBACK_REASON',
    ),
    caught(
      'mutation-misplaced-cache-marker-caught',
      'A cache marker parked on a step cannot state which lane it excuses, so it must be rejected as misplaced rather than read as an exemption.',
      PRECOMMIT,
      [
        {
          find: '      - name: Run pre-commit\n        run:',
          replace:
            '      - name: Run pre-commit\n        env:\n          NIX_CACHE_EXEMPT_REASON: probe-only misplaced marker\n        run:',
        },
      ],
      'job-level env',
    ),
    caught(
      'mutation-unreadable-shell-set-caught',
      "The set of shells a job may enter is read from nix/shells.nix rather than hardcoded in the gate, so the gate must refuse when it cannot read that set — otherwise its run: matcher would silently accept nothing, or everything. The mutation only DEDENTS the declarations: nix ignores the indentation, so the built shells stay byte-identical and this arm tests the gate's parser rather than the flake. The gate may anchor on that indentation precisely because `nix fmt` is itself a gate on this file.",
      SHELLS,
      [
        { find: '  cd = pkgs.mkShell {', replace: 'cd = pkgs.mkShell {' },
        { find: '  ci = pkgs.mkShell {', replace: 'ci = pkgs.mkShell {' },
        { find: '  default = pkgs.mkShell {', replace: 'default = pkgs.mkShell {' },
        { find: '  releaser = pkgs.mkShell {', replace: 'releaser = pkgs.mkShell {' },
      ],
      "either the shell set moved or this gate's parser is broken",
    ),
  ],
};
