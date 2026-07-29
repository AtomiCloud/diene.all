import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

// LANDSCAPE is what selects the overlay: AtomiConfigSource reads it when Landscape is blank,
// so without it the landscape layer is simply absent and the sabotage below would prove
// nothing about the MERGE.
const GATE = 'nix develop .#ci -c env LANDSCAPE=lapras pls config:validate';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-config-validate-green',
    description: 'Every option block binds and validates against the final merged layer.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-config-validate', 600000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-config-validate-caught',
    description: 'A schema-invalid landscape overlay makes the fail-fast validation red.',
    async run(repo: any) {
      // The overlay is the layer a landscape actually changes, so sabotaging THERE proves
      // the merge is validated rather than only the base file.
      await repo.write('App/Config/settings.lapras.yaml', 'server_engine:\n  webhook_tolerance: PT99H\n');
      await expectRed(repo, GATE, 'dotnet-api-config-validate', 600000);
    },
  },
});
