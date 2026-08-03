import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectSuccess } from './lib/exec.ts';

const smoke = 'nix develop --no-write-lock-file .#ci -c pls deadcode';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-deadcode-review-green',
      description: 'Both lax review passes run to completion and stay non-blocking.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectSuccess(repo, smoke);
        // A review pass that never ran also exits 0, so each pass has to say it happened.
        const output = `${result.stdout}\n${result.stderr}`;
        for (const marker of ['Repo dead-code review', 'Production dead-code review', 'Dead-code review complete']) {
          if (!output.includes(marker)) {
            throw new Error(`bun-deadcode-review did not report '${marker}':\n${output}`);
          }
        }
        for (const config of ['knip.llm.json', 'knip.production.llm.json']) {
          if ((await repo.glob(config)).length !== 1) {
            throw new Error(`the lax review variant ${config} is missing`);
          }
        }
      },
    },
  ],
};
