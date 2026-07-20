import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-dotnet-lib-vendored-skills',
    description: 'The namespaced usage skill exists and is included by both packable projects.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'test -f skills/diene-dotnet-note-usage/SKILL.md && rg -q \'Include="../skills/[*][*]"\' Lib/Lib.csproj TestHelper/TestHelper.csproj',
        'dotnet-lib-vendored-skills',
      );
    },
  },
});
