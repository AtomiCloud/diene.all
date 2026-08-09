import { commandGate } from './lib/cli-contract.ts';

export default commandGate(
  'cli-adapter-unit-seam',
  "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun test tests/unit/kv tests/unit/slug.test.ts'",
  {
    path: 'src/lib/kv/service.ts',
    find: '    return composed;',
    replace: '    return `${composed}-broken`;',
  },
);
