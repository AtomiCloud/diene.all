import { definePresence } from './lib/definition.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-bun-lib-usage-skill',
    description: 'The package usage skill and its ESM, CommonJS, and TestHelper guidance assets exist.',
    async run(repo: any) {
      for (const path of [
        'skills/diene-bun-lib-usage/SKILL.md',
        'skills/diene-bun-lib-usage/assets/consumer.ts',
        'skills/diene-bun-lib-usage/assets/consumer.cjs',
        'skills/diene-bun-lib-usage/assets/test-helper.md',
      ]) {
        if ((await repo.glob(path)).length !== 1) throw new Error(`${path} is missing`);
      }
    },
  },
});
