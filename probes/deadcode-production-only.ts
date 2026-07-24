import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the production-only dead-code pass rebuilds the package from its
// published entrypoints (tests excluded) so exports reachable only from tests
// are surfaced as dead code. This probe replicates that standalone pass inline
// (mirroring scripts/local/deadcode.sh) and proves a public export unreferenced
// by the production entrypoints is flagged.
const MEMBER = 'packages/diene_dart_lib';
const PRODUCTION_PASS = [
  'nix develop .#ci --no-write-lock-file -c bash -lc ',
  "'set -e; member=packages/diene_dart_lib; prod=$(mktemp -d); ",
  'cp "$member/analysis_options.yaml" "$prod/analysis_options.yaml"; ',
  'yq "del(.resolution)" "$member/pubspec.yaml" > "$prod/pubspec.yaml"; ',
  'cp -R "$member/lib" "$prod/lib"; mkdir -p "$prod/bin"; ',
  'cp "$member/tool/deadcode_entrypoints.dart" "$prod/bin/main.dart"; ',
  'cd "$prod"; dart pub get; ',
  'dart run dart_code_linter:metrics check-unused-code .; ',
  "dart run dart_code_linter:metrics check-unused-files .'",
].join('');

async function findBarrel(repo: any): Promise<string> {
  const candidates = (await repo.glob(`${MEMBER}/lib/*.dart`)).sort();
  for (const candidate of candidates) {
    if ((await repo.read(candidate)).includes("export 'src/")) {
      return candidate;
    }
  }
  throw new Error('deadcode-production-only: no library barrel exporting src/ found');
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci --no-write-lock-file -c dart pub get --offline || nix develop .#ci --no-write-lock-file -c dart pub get',
    ],
  },
  probes: [
    {
      name: 'baseline-deadcode-production-only-green',
      description: 'the production-only dead-code pass is clean on the pristine template',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, PRODUCTION_PASS, 'deadcode-production-only');
      },
    },
    {
      name: 'mutation-deadcode-production-only-caught',
      description: 'the production-only pass flags a public export unreachable from published entrypoints',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(
          `${MEMBER}/lib/src/probe_production_only.dart`,
          'int probeProductionOnly() {\n  return 1;\n}\n',
        );
        const barrel = await findBarrel(repo);
        await repo.write(barrel, `${await repo.read(barrel)}\nexport 'src/probe_production_only.dart';\n`);
        await expectRed(repo, PRODUCTION_PASS, 'deadcode-production-only');
      },
    },
  ],
};
