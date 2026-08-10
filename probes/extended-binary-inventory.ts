import { expectBunGreen } from './lib/bun-command.ts';

// Cost: medium (<2min) — a bun install plus five real invocations.
//
// This is the node-local companion to the inherited binary-smoke row: wrangler,
// the OpenNext adapter, bru, and playwright all arrive through node_modules
// rather than the Nix shell, so the inherited inventory cannot see them.
const command = 'nix develop .#ci -c ./scripts/validate/extended-binary-smoke.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-extended-binary-inventory-green',
      description: 'Every node-local binary the deploy and e2e rails depend on resolves and answers a real invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'extended-binary-inventory');
      },
    },
  ],
};
