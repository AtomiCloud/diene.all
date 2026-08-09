import { ConfigLoader, YamlConfigSource, type EnvRecord } from '@atomicloud/diene.e2e/config';
import { applicationRegistry, type ApplicationConfig } from './schema';

export interface LoadApplicationConfigOptions {
  readonly buildTimeEnv?: EnvRecord;
  readonly configDir: string;
  readonly environment?: EnvRecord;
  readonly landscape?: string;
  readonly prefix: string;
}

export async function loadApplicationConfig(options: LoadApplicationConfigOptions): Promise<ApplicationConfig> {
  const source = new YamlConfigSource({
    baseFile: 'settings.yaml',
    buildTimeEnv: options.buildTimeEnv,
    dir: options.configDir,
    env: options.environment,
    overlayFile: landscape => `${landscape}.settings.yaml`,
  });
  const loader = new ConfigLoader(source, applicationRegistry, {
    landscape: options.landscape,
    prefix: options.prefix,
  });
  const config = await loader.load();
  return config.all();
}
