import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  // dart-lib venue: skills-sync resolves the pub workspace to locate the member's
  // shipped usage skill; restore .dart_tool from the warm PUB_CACHE first so the
  // vendored copy is regenerated identically (otherwise skills-sync drops it).
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-skills-freshness-green',
      description: 'The vendored-skill freshness gate is green on synchronized output.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/skills-freshness.sh', 'skills-freshness');
      },
    },
    {
      name: 'mutation-skills-freshness-independent-oracle-caught',
      description: 'the independent oracle rejects a generator that agrees with its own incomplete vendor output',
      kind: 'mutation',
      expectedImpact: ['skills-sync'],
      async run(repo: any) {
        const cwd = await repo.exec('pwd');
        if (cwd.exitCode !== 0) {
          throw new Error(`skills-freshness-oracle: failed to resolve sandbox root: ${cwd.stderr || cwd.stdout}`);
        }
        await repo.write('.probe/hosted-package/skills/hosted/SKILL.md', '# Hosted probe\n');
        const packageConfig = JSON.parse(await repo.read('.dart_tool/package_config.json'));
        packageConfig.packages.push({
          name: 'diene_oracle_probe',
          rootUri: `file://${cwd.stdout.trim()}/.probe/hosted-package`,
          packageUri: 'lib/',
          languageVersion: '3.6',
        });
        await repo.write('.dart_tool/package_config.json', `${JSON.stringify(packageConfig, null, 2)}\n`);
        await repo.write(
          'scripts/local/skills-sync.sh',
          '#!/usr/bin/env bash\nset -euo pipefail\necho "broken generator left vendor unchanged"\n',
        );

        await expectRed(
          repo,
          'nix develop .#ci --no-write-lock-file -c ./scripts/validate/skills-freshness.sh',
          'skills-freshness-independent-oracle',
        );
      },
    },
  ],
};
