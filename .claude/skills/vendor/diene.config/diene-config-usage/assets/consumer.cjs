// CommonJS package-boundary example for @atomicloud/diene.config.
// Both `require` and `import` resolve; TypeScript picks .d.cts for require.
const { ConfigLoader, ConfigRegistry, YamlConfigSource } = require('@atomicloud/diene.config');
const { z } = require('zod');

const registry = ConfigRegistry.create().register('server', z.object({ port: z.coerce.number(), host: z.string() }));

async function main() {
  const source = new YamlConfigSource({ dir: 'config', env: process.env });
  const config = await new ConfigLoader(source, registry, { prefix: 'ATOMI_' }).load();
  console.log(config.get('server').host);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
