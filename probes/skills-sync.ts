import { expectGreen } from './lib/helpers.ts';

const packageConfigPath = '.dart_tool/package_config.json';
const hostedFixtureDir = '.probe/hosted package';
const vendorDir = '.claude/skills/vendor';
const syncCommand = 'nix develop .#ci --no-write-lock-file -c ./scripts/local/skills-sync.sh';

async function restoreHostedProbeWorld(repo: any, packageConfigSource: string): Promise<void> {
  await repo.write(packageConfigPath, packageConfigSource);

  const removed = await repo.exec(`git clean -fdx -- '${hostedFixtureDir}'`);
  if (removed.exitCode !== 0) {
    throw new Error(
      `skills-sync-hosted-cleanup: could not remove the hosted fixture: ${removed.stderr || removed.stdout}`,
    );
  }

  await expectGreen(repo, syncCommand, 'skills-sync-hosted-cleanup');

  const status = await repo.exec(`git status --porcelain=v1 --untracked-files=all -- ${vendorDir}`);
  if (status.exitCode !== 0) {
    throw new Error(
      `skills-sync-hosted-cleanup: could not inspect the restored vendor tree: ${status.stderr || status.stdout}`,
    );
  }
  if (status.stdout.trim().length !== 0) {
    throw new Error(`skills-sync-hosted-cleanup: restored vendor tree is not clean:\n${status.stdout}`);
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-skills-sync-green',
      description: 'the synchronizer is idempotent and resolves hosted file URIs into vendored skills',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('.claude/skills/vendor/stale/SKILL.md', 'stale\n');
        await expectGreen(
          repo,
          `nix develop .#ci -c bash -c 'first="$(mktemp -d)"; second="$(mktemp -d)"; trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; ./scripts/local/skills-sync.sh; test ! -e .claude/skills/vendor/stale; cp -R .claude/skills/vendor/. "$first"/; ./scripts/local/skills-sync.sh; cp -R .claude/skills/vendor/. "$second"/; diff -ru "$first" "$second"'`,
          'skills-sync',
        );

        const cwd = await repo.exec('pwd');
        if (cwd.exitCode !== 0) {
          throw new Error(`skills-sync: failed to resolve sandbox root: ${cwd.stderr || cwd.stdout}`);
        }
        const packageConfigSource = await repo.read(packageConfigPath);
        try {
          await repo.write(`${hostedFixtureDir}/skills/hosted/SKILL.md`, '# Hosted probe\n');
          const packageConfig = JSON.parse(packageConfigSource);
          packageConfig.packages.push({
            name: 'diene_hosted_probe',
            rootUri: `file://${cwd.stdout.trim()}/.probe/hosted%20package`,
            packageUri: 'lib/',
            languageVersion: '3.6',
          });
          await repo.write(packageConfigPath, `${JSON.stringify(packageConfig, null, 2)}\n`);

          await expectGreen(repo, syncCommand, 'skills-sync-hosted-file-uri');
          if ((await repo.glob(`${vendorDir}/diene_hosted_probe/hosted/SKILL.md`)).length !== 1) {
            throw new Error('skills-sync-hosted-file-uri: hosted skills were not vendored');
          }
        } finally {
          await restoreHostedProbeWorld(repo, packageConfigSource);
        }
      },
    },
  ],
};
