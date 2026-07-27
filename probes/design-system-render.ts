import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — one `next build`. Rendering every rule-defaulting component through
// a real build is the proof that the design system compiles and prerenders; there is
// deliberately no screenshot or golden comparison anywhere in this tree.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh\'';

// A FILE artifact must exist exactly once.
const FILE_ARTIFACTS = ['.next/standalone/server.js'];

// DIRECTORY artifacts are asserted by their CONTENTS, not by the bare directory path.
//
// cyanprint 4.9.0's `repo.glob` does not match a bare directory, so
// `glob('.next/server/app')` returned 0 for a directory that demonstrably exists —
// which failed this baseline and, because every other row's control depends on it,
// poisoned two entire 198-row matrices with 197 cascade rows apiece.
//
// Globbing for content is also a STRONGER assertion than the one it replaces:
// `glob('.next/server/app').length === 1` passes on an EMPTY directory, which is
// exactly what a broken build leaves behind. Requiring real chunks inside proves the
// thing this probe's own description claims — that the app compiled and prerendered.
//
// `.js` chosen by measuring the build rather than guessing: 38, 41 and 41 files
// respectively in a local production build.
const DIR_ARTIFACTS = [
  '.next/server/app/**/*.js',
  '.next/static/**/*.js',
  // `output: 'standalone'` traces the server but ships neither public/ nor
  // .next/static — the assets step copies both, and an app without client chunks
  // boots and then renders nothing.
  '.next/standalone/.next/static/**/*.js',
];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-design-system-render-green',
      description:
        'The app builds and prerenders: every page and rule-defaulting component compiles, and the standalone artifact carries its server and client chunks.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'design-system-render');
        for (const artifact of FILE_ARTIFACTS) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`build produced no ${artifact}`);
          }
        }
        for (const artifact of DIR_ARTIFACTS) {
          // At LEAST one match: these are directory contents, so an exact-one check
          // would be wrong in the other direction — a healthy build puts dozens of
          // chunks in each of these.
          if ((await repo.glob(artifact)).length < 1) {
            throw new Error(`build produced nothing matching ${artifact}`);
          }
        }
      },
    },
  ],
};
