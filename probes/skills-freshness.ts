import { capturedEnvCommand, expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const vendorDir = '.claude/skills/vendor';
const freshnessCommand = 'nix develop .#ci -c dlint skills-fresh';
const probeCleanTargets = [
  vendorDir,
  'node_modules/@atomicloud/diene.readonly',
  'node_modules/@atomicloud/diene.untracked',
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

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-skills-freshness-green',
      description:
        'The vendored-skill freshness gate has a tracked subject beyond .gitkeep and is green on synchronized output.',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, probeCleanTargets, async () => {
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
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write(`${vendorDir}/stale/SKILL.md`, 'stale\n');
          const staged = await repo.exec(`git add ${vendorDir}/stale/SKILL.md`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the stale vendored-skill fixture: ${staged.stderr || staged.stdout}`);
          }
          await expectRedBecause(repo, freshnessCommand, 'skills-freshness', [
            'vendored tree is stale',
            `${vendorDir}/stale/SKILL.md`,
          ]);
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
        await withCleanProbeState(repo, probeCleanTargets, async () => {
          await repo.write('node_modules/@atomicloud/diene.untracked/skills/example/SKILL.md', 'untracked skill\n');
          const result = await repo.exec(capturedEnvCommand(freshnessCommand), { timeoutMs: 240000 });
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
  ],
};
