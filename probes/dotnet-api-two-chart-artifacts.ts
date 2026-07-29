import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

// goals/dotnet-api.md L74: two chart artifacts [presence] — the app AND primordial chart roots
// and their REQUIRED RESOURCE FILES exist. Two roots, so the row asserts BOTH: a single-chart
// repo must not satisfy a row whose whole point is that there are two.
//
// Presence rows are exists-only and have no sabotage arm, which makes them the easiest place to
// write something vacuous. The specific hazard here is `test -f` on a path that was never going
// to be missing. So each required file is asserted BY NAME and the row PRINTS the count it
// checked, and a missing one names which chart and which file.
const REQUIRED: Record<string, string[]> = {
  'infra/root_chart': [
    'Chart.yaml',
    'values.yaml',
    'values.schema.json',
    'templates/deployment.yaml',
    'templates/service.yaml',
    'templates/httproute.yaml',
    'templates/externalsecret.yaml',
    'templates/dbinit-job.yaml',
  ],
  'infra/primordial_chart': [
    'Chart.yaml',
    'values.yaml',
    'values.schema.json',
    'templates/platformdependency.yaml',
    'templates/problems.yaml',
    'templates/logtoapp.yaml',
  ],
};

const checks = Object.entries(REQUIRED)
  .flatMap(([chart, files]) =>
    files.map(file => `test -f "${chart}/${file}" || { echo "MISSING ${chart}/${file}"; exit 1; }; n=$((n+1)); `),
  )
  .join('');

const EXPECTED = Object.values(REQUIRED).reduce((total, files) => total + files.length, 0);

// EXPECTED is DERIVED FROM REQUIRED, so on its own it cannot detect REQUIRED being emptied:
// `n` and EXPECTED would both be 0 and the equality would hold while nothing was asserted. A
// positive control proved exactly that — the row passed with an empty list. FLOOR and CHARTS are
// LITERALS, independent of the list, so a gutted list fails against something it cannot move.
const FLOOR = 12;
const CHARTS = 2;

const GATE =
  `bash -c 'set -e; n=0; ` +
  // Both roots first, so a missing chart reports as a missing CHART rather than as a pile of
  // missing files.
  Object.keys(REQUIRED)
    .map(chart => `test -d "${chart}" || { echo "MISSING chart root ${chart}"; exit 1; }; `)
    .join('') +
  checks +
  `test "$n" -eq ${EXPECTED} || { echo "checked $n files, expected ${EXPECTED}"; exit 1; }; ` +
  // The literal floor, which an emptied list cannot satisfy by shrinking alongside it.
  `test "$n" -ge ${FLOOR} || { echo "checked only $n files, floor is ${FLOOR}"; exit 1; }; ` +
  `echo "both chart roots present; ${EXPECTED} required resource file(s) verified"'`;

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-two-chart-artifacts-present',
    description: 'Both chart roots and every required resource file exist.',
    async run(repo: any) {
      // Checked here rather than at module scope so a gutted list reports as a probe FAILURE
      // instead of crashing the loader before any verdict exists.
      if (Object.keys(REQUIRED).length !== CHARTS) {
        throw new Error(`REQUIRED must cover BOTH chart roots; it lists ${Object.keys(REQUIRED).length}`);
      }
      if (EXPECTED < FLOOR) {
        throw new Error(`REQUIRED lists only ${EXPECTED} files; the floor is ${FLOOR}`);
      }
      await expectGreen(repo, GATE, 'dotnet-api-two-chart-artifacts', 120000);
    },
  },
});
