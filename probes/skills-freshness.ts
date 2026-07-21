import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
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
      name: 'mutation-skills-freshness-caught',
      description: 'A focused sabotage must turn the skills-freshness mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('.claude/skills/vendor/stale/SKILL.md', 'stale\n');
        await repo.exec('git add .claude/skills/vendor/stale/SKILL.md');
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/skills-freshness.sh', 'skills-freshness');
      },
    },
  ],
};
