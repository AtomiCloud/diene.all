import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-lax-report-green',
      description: 'The LLM-lax deadcode feed emits a nonblocking review artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c bash -lc "./scripts/local/deadcode.sh lax && test -s reports/deadcode-llm.txt"',
          'deadcode-llm-lax',
        );
      },
    },
  ],
};
