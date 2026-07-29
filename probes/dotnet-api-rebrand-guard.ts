import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const GATE = 'nix develop .#ci -c ./scripts/validate/rebrand.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-rebrand-guard-green',
    description: 'Every identity, branding and auth value is config-driven, not written in C#.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-rebrand-guard', 240000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-rebrand-guard-caught',
    description: 'Hardcoding a configured identity value into a C# source turns the guard red.',
    async run(repo: any) {
      // Structural target: read the service name OUT of configuration and plant that exact
      // literal, so the sabotage cannot drift away from what the gate reads.
      const settings = await repo.read('App/Config/settings.yaml');
      const service = settings.match(/^\s{2}service:\s*(\S+)\s*$/m)?.[1];
      if (!service) throw new Error('App/Config/settings.yaml no longer declares app:service');

      const sources = await repo.glob('App/**/*.cs');
      if (sources.length === 0) throw new Error('no App C# sources to plant a hardcoded identity in');

      const path = sources[0];
      const source = await repo.read(path);
      await repo.write(path, `${source}\n// probe: hardcoded identity "${service}"\n`);

      await expectRed(repo, GATE, 'dotnet-api-rebrand-guard', 240000);
    },
  },
});
