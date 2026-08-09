import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-dotnet-codecov-config',
    description: 'Informational unit/int flags use convention-based Lib*/App* paths.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c yq -e '.coverage.status.project.default.informational == true and .coverage.status.patch.default.informational == true and (.flags.unit.paths | length) == 1 and .flags.unit.paths[0] == "Lib*/" and (.flags.int.paths | length) == 1 and .flags.int.paths[0] == "App*/" and .flags.unit.carryforward == true and .flags.int.carryforward == true' codecov.yml`,
        'dotnet-codecov-config',
      );
    },
  },
});
