import { expectGreen, expectRed, withCleanProbeState } from './lib/helpers.ts';

const vendorDir = '.claude/skills/vendor';
const freshnessCommand = 'nix develop .#ci -c ./scripts/validate/skills-freshness.sh';
const offlinePubGetCommand = 'nix develop .#ci --no-write-lock-file -c dart pub get --offline';
const probeCleanTargets = [
  vendorDir,
  'node_modules/@atomicloud/diene.readonly',
  'node_modules/@atomicloud/diene.untracked',
  '.probe/hosted-package',
  '.dart_tool',
  'package.json',
  'go.mod',
  'go-shim',
];

async function trackedSubjects(repo: any): Promise<string[]> {
  const listed = await repo.exec(`git ls-files -- ${vendorDir}`);
  if (listed.exitCode !== 0) {
    throw new Error(`could not list tracked vendored skills: ${listed.stderr || listed.stdout}`);
  }
  return listed.stdout
    .split('\n')
    .map((line: string) => line.trim())
    .filter((line: string) => line.length > 0 && line !== `${vendorDir}/.gitkeep`);
}

async function withResolvedFreshnessState(repo: any, body: () => Promise<void>): Promise<void> {
  await withCleanProbeState(repo, probeCleanTargets, async () => {
    // The leading clean deliberately removes .dart_tool, so rebuild the
    // resolver inventory inside each arm from the already-warm shared cache.
    await expectGreen(repo, offlinePubGetCommand, 'skills-freshness-resolver-setup');
    await body();
  });
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [offlinePubGetCommand],
  },
  probes: [
    {
      name: 'baseline-skills-freshness-green',
      description:
        'The vendored-skill freshness gate has a tracked subject beyond .gitkeep and is green on synchronized output.',
      kind: 'baseline',
      async run(repo: any) {
        await withResolvedFreshnessState(repo, async () => {
          const subjects = await trackedSubjects(repo);
          if (subjects.length === 0) {
            throw new Error(`the freshness gate has no tracked subject under ${vendorDir} beyond .gitkeep`);
          }
          await expectGreen(repo, freshnessCommand, 'skills-freshness');
        });
      },
    },
    {
      name: 'mutation-skills-freshness-caught',
      description: 'A focused sabotage must turn the skills-freshness mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withResolvedFreshnessState(repo, async () => {
          await repo.write(`${vendorDir}/stale/SKILL.md`, 'stale\n');
          const staged = await repo.exec(`git add ${vendorDir}/stale/SKILL.md`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the stale vendored-skill fixture: ${staged.stderr || staged.stdout}`);
          }
          await expectRed(repo, freshnessCommand, 'skills-freshness');
        });
      },
    },
    {
      name: 'mutation-skills-freshness-untracked-caught',
      description:
        'A focused sabotage must turn the skills-freshness mechanism red: a resolver input that regenerates an untracked vendored skill must be reported, not silently ignored by a tracked-only diff.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withResolvedFreshnessState(repo, async () => {
          await repo.write('node_modules/@atomicloud/diene.untracked/skills/example/SKILL.md', 'untracked skill\n');
          const result = await repo.exec(freshnessCommand, { timeoutMs: 240000 });
          if (result.exitCode === 0) {
            throw new Error('skills-freshness stayed green after an untracked vendored-skill regeneration');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          const entry = `?? ${vendorDir}/diene.untracked/example/SKILL.md`;
          if (!output.includes(entry)) {
            throw new Error(`skills-freshness did not report '${entry}':\n${output}`);
          }
        });
      },
    },
    {
      name: 'mutation-skills-freshness-independent-oracle-caught',
      description: 'The independent Pub oracle rejects a generator that agrees with its own incomplete vendor output.',
      kind: 'mutation',
      expectedImpact: ['skills-sync'],
      async run(repo: any) {
        await withResolvedFreshnessState(repo, async () => {
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

          const result = await repo.exec(
            'nix develop .#ci --no-write-lock-file -c ./scripts/validate/skills-freshness.sh',
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('skills-freshness independent oracle stayed green after the incomplete generator');
          }
          const output = `${result.stdout}\n${result.stderr}`;
          if (
            !output.includes('Dart package diene_oracle_probe has skills but no matching nonempty vendored directory')
          ) {
            throw new Error(`skills-freshness independent oracle failed for the wrong reason:\n${output}`);
          }
        });
      },
    },
  ],
};
