import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const GATE = 'nix develop .#ci -c pls problems:verify';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-problem-catalog-green',
    description: 'The exported Problem resources match the registered catalog.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-problem-catalog', 600000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-problem-catalog-caught',
    description: 'Changing the catalog without re-exporting turns the drift check red.',
    async run(repo: any) {
      // Sabotage the SOURCE, not the export: the gate exists to catch a catalog change that
      // was never exported, which is the direction a real drift arrives from.
      const path = 'App/Error/ServiceProblems.cs';
      const source = await repo.read(path);
      const anchor = 'catalog.AddBaseline();';
      if (!source.includes(anchor)) throw new Error(`${path} no longer registers the baseline catalog`);
      await repo.write(path, source.replace(anchor, ''));

      await expectRed(repo, GATE, 'dotnet-api-problem-catalog', 600000);
    },
  },
});
