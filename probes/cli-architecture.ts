import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-architecture', 'arch', {
  path: 'src/lib/kv/service.ts',
  find: '/** Domain logic over the key-value store — zero IO beyond the injected ports. */',
  replace:
    "console.log('architecture violation');\n/** Domain logic over the key-value store — zero IO beyond the injected ports. */",
});
