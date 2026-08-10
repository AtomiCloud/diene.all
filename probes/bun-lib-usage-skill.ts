import { definePresence } from './lib/definition.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-bun-lib-usage-skill',
    description: 'The frontend-utils usage skill and its consumer and TestHelper assets exist.',
    async run(repo: any) {
      for (const path of [
        'skills/diene-frontend-utils-usage/SKILL.md',
        'skills/diene-frontend-utils-usage/agents/openai.yaml',
        'skills/diene-frontend-utils-usage/assets/consumer.ts',
        'skills/diene-frontend-utils-usage/assets/consumer-test.ts',
      ]) {
        if ((await repo.glob(path)).length !== 1) throw new Error(`${path} is missing`);
      }
    },
  },
});
