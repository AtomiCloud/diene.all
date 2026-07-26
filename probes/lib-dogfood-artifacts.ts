export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-lib-dogfood-artifacts-present',
      description: 'The published train dependency declaration and its vendored usage skills exist.',
      kind: 'baseline',
      async run(repo: any) {
        const manifest = JSON.parse(await repo.read('package.json'));
        const declared = manifest.dependencies?.['@atomicloud/diene.e2e'];
        if (declared !== '1.1.0') {
          throw new Error(`package.json must pin @atomicloud/diene.e2e at exactly 1.1.0, found ${declared}`);
        }
        const skills = await repo.glob('.claude/skills/vendor/diene.*/**/SKILL.md');
        if (skills.length < 10) {
          throw new Error(
            `expected vendored usage skills for the train members, found ${skills.length} SKILL.md files`,
          );
        }
      },
    },
  ],
};
