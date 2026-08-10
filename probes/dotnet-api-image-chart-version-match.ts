import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

// goals/dotnet-api.md L49: image/chart version match [gate] — ONE semver spans the image, both
// chart `Version` fields, and `appVersion`; sabotage: mismatch one version -> static check red.
const GATE = `nix develop .#ci -c ./scripts/validate/chart-versions.sh`;

// Asserted by the mutation arm so `caught` cannot be satisfied by an unrelated failure. The
// script refuses on absent files and absent fields with different messages, so a red caused by
// a missing chart would NOT match this needle — which is the point. Verified directly that a
// mismatching run prints it and a healthy run does not.
const REASON = 'does not equal VERSION=';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-image-chart-version-match-green',
    description: 'One semver spans the image tag and both charts, checked field by field.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-image-chart-version-match', 240000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-image-chart-version-match-caught',
    description: 'Mismatching one chart version against VERSION turns the static check red.',
    async run(repo: any) {
      // Structural target: drift ONE of the five fields the gate compares, chosen so the
      // sabotage is a realistic missed bump rather than a malformed file. Read the current
      // value first and assert it changed, so a version that is already 9.9.9 cannot make
      // this a silent no-op.
      const path = 'infra/primordial_chart/Chart.yaml';
      const before = await repo.read(path);
      const line = /^version:.*$/m;
      if (!line.test(before)) throw new Error(`${path} declares no top-level 'version' field`);
      const after = before.replace(line, 'version: 9.9.9');
      if (after === before) throw new Error(`${path} version was already 9.9.9 — sabotage would be a no-op`);

      await repo.write(path, after);
      await expectRedBecause(repo, GATE, 'dotnet-api-image-chart-version-match', [REASON], { timeoutMs: 240000 });
    },
  },
});
