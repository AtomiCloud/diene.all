import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-adapter-integration-seam',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun test --config=bunfig.int.toml'",
  {
    path: 'src/adapters/kv/data/redis-kv-store.ts',
    find: '    return this.client.get(key);',
    replace: '    return null;',
  },
);
