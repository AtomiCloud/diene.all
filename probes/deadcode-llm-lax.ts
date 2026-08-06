import { expectGreen } from './lib/helpers.ts';

// Every scanner pass records its own completion line, so a header-only or truncated report cannot read as a clean one.
const passes = [
  'whole-repository staticcheck',
  'whole-repository deadcode',
  'production staticcheck',
  'production deadcode',
];
const evidence = passes.map(pass => `grep -qF '## pass complete: ${pass} (' reports/deadcode-llm.txt`).join(' && ');
// Drop the artifact first so the evidence can only have come from this run.
const gate = `nix develop .#ci -c bash -lc "rm -f reports/deadcode-llm.txt && ./scripts/local/deadcode.sh lax && ${evidence}"`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-lax-report-green',
      description: 'The LLM-lax deadcode feed emits a nonblocking review artifact recording all four scanner passes.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-llm-lax');
      },
    },
  ],
};
