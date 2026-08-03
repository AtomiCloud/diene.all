import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectSuccess } from './lib/exec.ts';

// One row, two invocations: the goal's run surface is a single mechanism and both halves must answer.
const invocations = [
  { task: 'run', command: 'nix develop --no-write-lock-file .#ci -c pls run --' },
  { task: 'preview', command: 'nix develop --no-write-lock-file .#ci -c pls preview --' },
];

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-run-green',
      description: 'The sample answers a real invocation from source and from the built bundle.',
      kind: 'baseline',
      async run(repo: any) {
        for (const invocation of invocations) {
          const result = await expectSuccess(repo, invocation.command);
          // Exit 0 with no output is what a task that resolved to nothing looks like.
          if (result.stdout.trim() === '') {
            throw new Error(`pls ${invocation.task} exited 0 without producing any output`);
          }
        }
      },
    },
  ],
};
