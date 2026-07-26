// ESM package-boundary example for @atomicloud/diene.config.
// Import the package root only — never reach into src/ or dist/.
import { ConfigLoader, ConfigRegistry, YamlConfigSource } from '@atomicloud/diene.config';
import { z } from 'zod';

// Each engine/library owns its block schema; a service composes them.
const ServerBlock = z.object({
  port: z.coerce.number(), // coerce so an env string like "8080" becomes a number (M31)
  host: z.string(),
  tags: z.array(z.string()),
});

const registry = ConfigRegistry.create().register('server', ServerBlock);

const source = new YamlConfigSource({
  dir: 'config', // holds config.yaml (full defaults) + <landscape>.config.yaml overlays
  env: process.env, // runtime overrides: ATOMI_SERVER__PORT, ATOMI_SERVER__TAGS__0, ...
});

const config = await new ConfigLoader(source, registry, {
  prefix: 'ATOMI_', // REQUIRED — no baked default
  landscape: process.env.LANDSCAPE, // host supplies the landscape; the lib never detects it
}).load();

// Typed access — all three forms are equivalent for the block value.
const server = config.get('server');
console.log(server.host, server.port, server.tags);
