import { expectGreen } from './lib/helpers.ts';

// Smoke: the pub workspace resolves from the repo root and produces a package
// config listing the workspace members.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-pub-workspace-resolution-green',
      description: 'dart pub get resolves the workspace and writes a package config',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c dart pub get --offline',
          'pub-workspace-resolution',
        );
        const config = JSON.parse(await repo.read('.dart_tool/package_config.json'));
        if (!Array.isArray(config.packages) || config.packages.length === 0) {
          throw new Error('pub-workspace-resolution: package_config.json lists no packages');
        }
      },
    },
  ],
};
