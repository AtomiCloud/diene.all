import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-build-artifact-green',
      description: 'The build task emits an executable that performs a real command.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          // REBRAND FIX 2026-07-27. This probe is inherited from diene/go-base and
          // carried that template's binary name AND a `slug` subcommand this node
          // does not implement. Measured: scripts/local/build.sh emits
          // dist/go-consumer (never dist/go-base), and `./dist/go-consumer slug`
          // returns 'unknown command "slug" for "go-consumer"'. So the assertion
          // could never pass here — and because build-artifact is a SHARED CONTROL,
          // its failure marked 33 rows baseline_run_untrusted and 21 control_failed,
          // invalidating a whole 55-selector chunk: 0 proven, 57 broken.
          // `help` is used because it exercises the real cobra command surface
          // without requiring Redis or Postgres, keeping this a build smoke test.
          "nix develop .#ci -c bash -lc './scripts/local/build.sh && test -x dist/go-consumer && ./dist/go-consumer help >/dev/null'",
          'build-artifact',
        );
      },
    },
  ],
};
