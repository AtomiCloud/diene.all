import type { ProbeDefinition } from '@cyanprint/contracts';
import { capturedEnvCommand } from './lib/helpers.ts';

const gate = 'nix develop --no-write-lock-file .#default -c pre-commit run treefmt --all-files';

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'treefmt-prettier-baseline-green',
      description: 'The generated treefmt hook passes Prettier on the healthy root sample.',
      kind: 'baseline',
      timeoutMs: 240000,
      async run(repo) {
        const result = await repo.exec(capturedEnvCommand(gate), { timeoutMs: 240000 });
        if (result.exitCode !== 0) {
          throw new Error(`treefmt Prettier baseline failed: ${result.stderr || result.stdout}`);
        }
      },
    },
    {
      name: 'prettier-violation-reddens-treefmt-hook',
      description: 'A valid but unformatted JSON document must turn the Prettier member red.',
      kind: 'mutation',
      timeoutMs: 240000,
      async run(repo) {
        await repo.write('probe-prettier.json', '{"probe":true}\n');
        const staged = await repo.exec('git add probe-prettier.json');
        if (staged.exitCode !== 0) {
          throw new Error(`failed to stage Prettier fixture: ${staged.stderr || staged.stdout}`);
        }
        const result = await repo.exec(capturedEnvCommand(gate), { timeoutMs: 240000 });
        if (result.exitCode === 0) {
          throw new Error('treefmt Prettier stayed green after an unformatted JSON document');
        }
      },
    },
  ],
};

export default definition;
