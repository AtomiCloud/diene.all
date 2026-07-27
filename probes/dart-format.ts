import { expectGreen, expectRed, preserveMutationBeforeRestore } from './lib/helpers.ts';

// Gate: `dart format --set-exit-if-changed` keeps the whole tree canonically
// formatted. Sabotage appends an intentionally mis-spaced (but valid)
// declaration to a materialized library source file and proves the formatter
// flags the drift.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dart-format-green',
      description: 'dart format reports the pristine template as already formatted',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci --no-write-lock-file -c dart format --output=none --set-exit-if-changed .',
          'dart-format',
        );
      },
    },
    {
      name: 'mutation-dart-format-caught',
      description: 'dart format fails once a library source file drifts from canonical style',
      kind: 'mutation',
      expectedImpact: ['pana-score'],
      async run(repo: any) {
        const sources = (await repo.glob('packages/*/lib/src/**/*.dart')).sort();
        const target = sources[0];
        if (!target) {
          throw new Error('dart-format: no library source file to sabotage');
        }
        const original = await repo.read(target);
        try {
          await repo.write(target, `${original}\nfinal int probeUnformatted =  1;\n`);
          await expectRed(
            repo,
            'nix develop .#ci --no-write-lock-file -c dart format --output=none --set-exit-if-changed .',
            'dart-format',
          );
        } finally {
          await preserveMutationBeforeRestore(repo, 'dart-format', target, original);
        }
      },
    },
  ],
};
