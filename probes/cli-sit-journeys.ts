import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-sit-journeys',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls test:sit'",
  {
    path: 'src/adapters/kv/api/seed-controller.ts',
    find: '      this.io.success(`seeded ${parsed.data} entries under "${namespace}"`);',
    replace: '      this.io.success(`broken ${parsed.data} entries under "${namespace}"`);',
  },
);
