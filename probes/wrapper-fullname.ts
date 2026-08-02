import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

// The primary override must agree with the module slot it is derived from, and the
// refusal quotes both names, so the mutation below can assert the exact diagnostic.
const staleOverrideRefusal = 'fullnameOverride must be "wrapper-maincache", got "wrapper-api"';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-fullname-green',
    description: 'Rendered names and dependency overrides use service plus one dash plus fused token.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh fullname', 'wrapper-fullname');
    },
  },
  mutation: {
    name: 'mutation-wrapper-fullname-caught',
    description: 'A module rename that leaves the primary override behind is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        // Rename only the module slot. `wrapper-api` remains a schema-valid
        // `fullnameOverride` and `maincache` a schema-valid module, so the values
        // schema cannot be what turns this red — a sabotage the schema rejects
        // never reaches the helper and proves nothing about it. The leading and
        // trailing newlines pin the two-space service-tree slot rather than the
        // four-space LPSM contract slot further down the same file.
        await repo.patch(path, { find: '\n  module: api\n', replace: '\n  module: maincache\n' });
        const result = await repo.exec('nix develop .#ci -c ./scripts/validate/helm-wrapper.sh fullname', {
          timeoutMs: 240000,
        });
        if (result.exitCode === 0) {
          throw new Error('wrapper-fullname stayed green after sabotage');
        }
        const output = `${result.stdout}\n${result.stderr}`;
        if (!output.includes(staleOverrideRefusal)) {
          throw new Error(`wrapper-fullname did not report '${staleOverrideRefusal}':\n${output}`);
        }
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
