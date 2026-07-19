import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-sit-journeys',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:sit'",
  {
    path: 'src/adapters/kv/api/set-controller.ts',
    find: '      this.io.success(`set ${composed} = ${value}${ttlNote}`);',
    replace: '      this.io.success(`broken ${composed} = ${value}${ttlNote}`);',
  },
);
