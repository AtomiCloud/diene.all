import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: `scripts/ci/analyze.sh` runs `flutter analyze --fatal-infos
// --fatal-warnings` across the workspace. Sabotage injects a lint-violating
// declaration (`print` + unused element) into a library source file and proves
// the analyzer escalates it to a failure.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c flutter pub get --offline || nix develop .#ci --no-write-lock-file -c flutter pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-dart-analyze-green',
      description: 'flutter analyze passes on the pristine template with infos/warnings fatal',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci --no-write-lock-file -c ./scripts/ci/analyze.sh', 'dart-analyze');
      },
    },
    {
      name: 'mutation-dart-analyze-caught',
      description: 'flutter analyze fails when a library source file introduces a lint violation',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const sources = (await repo.glob('packages/*/lib/src/**/*.dart')).sort();
        const target = sources[0];
        if (!target) {
          throw new Error('dart-analyze: no library source file to sabotage');
        }
        const original = await repo.read(target);
        await repo.write(target, `${original}\nvoid _probeAnalyzeViolation() {\n  print('probe');\n}\n`);
        await expectRed(repo, 'nix develop .#ci --no-write-lock-file -c ./scripts/ci/analyze.sh', 'dart-analyze');
      },
    },
  ],
};
