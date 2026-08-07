import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-direnv-green',
      description: 'The committed .envrc loads the repository environment with an isolated direnv config.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'config="$(mktemp -d)" && DIRENV_CONFIG="$config" direnv allow . && DIRENV_CONFIG="$config" direnv exec . true',
          'direnv',
        );
      },
    },
  ],
};
