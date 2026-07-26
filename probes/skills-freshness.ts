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
        const paths = await repo.glob('.claude/skills/vendor/**/SKILL.md');
        if (paths.length === 0) {
          throw new Error('no committed vendored skill found');
        }
        const path = paths.sort()[0];
        const source = await repo.read(path);
        await repo.write(path, `${source.trimEnd()}\n\nstale vendored content\n`);
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/skills-freshness.sh', 'skills-freshness');
      },
    },
  ],
};
