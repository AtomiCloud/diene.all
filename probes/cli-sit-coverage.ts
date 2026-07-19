import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-sit-coverage',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:sit:coverage'",
  {
    path: 'bunfig.sit.toml',
    find: 'coverageDir = "coverage/sit"',
    replace: 'coverageDir = "coverage/wrong"',
  },
);
