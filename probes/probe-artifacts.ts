// The previous version iterated `features.json` to validate `features.json`. An empty file loops
// ZERO times, every per-feature check vanishes, and the row passed having asserted nothing beyond
// the helper library existing. Measured, not inferred: emptying the file to `[]` passed, while
// deleting one declared feature's probe file failed, so the loop itself worked — what was missing
// was any statement about the loop having anything to iterate.
//
// AN EXPECTATION COMPUTED FROM THE THING IT VALIDATES CANNOT DETECT THAT THING BEING GUTTED. The
// floor below is therefore a LITERAL, checked BEFORE the loop, and deliberately conservative: the
// inherited workspace and shared rows alone far exceed it on every base, so it fails on an emptied
// or truncated declaration file without tracking the real count as it grows.
const MIN_FEATURES = 20;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-probe-artifacts',
      description: 'Features are declared, each has a probe definition, and the shared helper library exists.',
      kind: 'baseline',
      async run(repo: any) {
        const features = JSON.parse(await repo.read('probes/features.json'));

        if (!Array.isArray(features)) {
          throw new Error('probes/features.json is not an array');
        }
        if (features.length < MIN_FEATURES) {
          throw new Error(
            `probes/features.json declares only ${features.length} feature(s), below the floor of ` +
              `${MIN_FEATURES}; an emptied or truncated declaration file would otherwise make every ` +
              `per-feature check below vanish and this row pass having asserted nothing`,
          );
        }

        for (const feature of features) {
          const paths = await repo.glob(`probes/${feature.name}.ts`);
          if (paths.length !== 1) {
            throw new Error(`missing probe definition for ${feature.name}`);
          }
        }
        if ((await repo.glob('probes/lib/helpers.ts')).length !== 1) {
          throw new Error('shared probe helpers are missing');
        }

        // Report WHAT was verified, so the row cannot read as a pass that checked nothing.
        console.log(`verified probe definitions for ${features.length} declared feature(s)`);
      },
    },
  ],
};
