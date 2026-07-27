import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the production-only dead-code pass rebuilds the package from its
// published entrypoints (tests excluded) so exports reachable only from tests
// are surfaced as dead code. This probe replicates that standalone pass inline
// (mirroring scripts/local/deadcode.sh) and proves a public export unreferenced
// by the production entrypoints is flagged.
const MEMBER = 'packages/diene_api_engine';
const PRODUCTION_PASS = [
  'nix develop .#ci --no-write-lock-file -c bash -lc ',
  "'set -e; member=packages/diene_api_engine; prod=$(mktemp -d); ",
  'cp "$member/analysis_options.yaml" "$prod/analysis_options.yaml"; ',
  'yq "del(.resolution)" "$member/pubspec.yaml" > "$prod/pubspec.yaml"; ',
  'cp -R "$member/lib" "$prod/lib"; mkdir -p "$prod/bin"; ',
  'cp "$member/tool/deadcode_entrypoints.dart" "$prod/bin/main.dart"; ',
  'cd "$prod"; flutter pub get; ',
  'flutter pub run dart_code_linter:metrics check-unused-code .; ',
  "flutter pub run dart_code_linter:metrics check-unused-files .'",
].join('');

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
        // Add a library file referenced ONLY by a test. In the whole-package view
        // the test keeps it live, but the production-only pass excludes tests, so
        // check-unused-files surfaces it as dead. (An unused top-level function is
        // NOT flagged by check-unused-code, so the sabotage must be a file.)
        await repo.write(`${MEMBER}/lib/src/probe_production_only.dart`, 'int probeProductionOnly() => 1;\n');
        await repo.write(
          `${MEMBER}/test/unit/probe_production_only_test.dart`,
          "import 'package:diene_api_engine/src/probe_production_only.dart';\n" +
            "import 'package:test/test.dart';\n\n" +
            "void main() {\n  test('probe production only', () {\n    expect(probeProductionOnly(), 1);\n  });\n}\n",
        );
        await expectRed(repo, PRODUCTION_PASS, 'deadcode-production-only');
      },
    },
  ],
};
