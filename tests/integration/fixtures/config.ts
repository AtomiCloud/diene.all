import { YamlConfigSource, loadConfig } from '@atomicloud/diene.config';
import { configRegistry } from '../../../src/config';
import type { RootConfig } from '../../../src/adapters/server-config';

/**
 * Load the repo's real config tree for the int tier. The adapters under test
 * consume a validated `RootConfig`, so specs load the shipped `config/` rather
 * than hand-rolling a config shape that could drift from the schema.
 */
export const intConfig = async (landscape = 'base'): Promise<RootConfig> =>
  (await loadConfig(new YamlConfigSource({ dir: `${process.cwd()}/config` }), configRegistry, {
    prefix: 'ATOMI_',
    landscape,
  })) as RootConfig;
