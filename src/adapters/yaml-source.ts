import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { type ConfigRecord, isRecord } from '../lib/merge.js';
import type { ConfigSource, EnvRecord } from '../lib/source.js';

export class YamlConfigSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'YamlConfigSourceError';
  }
}

export interface YamlConfigSourceOptions {
  /** Directory holding the config YAML files. */
  dir: string;
  /** Base file (full defaults). Default `config.yaml`. */
  baseFile?: string;
  /** Overlay file name for a landscape. Default `<landscape>.config.yaml`. */
  overlayFile?: (landscape: string) => string;
  /** Runtime env source. Default `process.env`. */
  env?: EnvRecord;
  /** Build-time injected env map (frozen at build). Default `{}`. */
  buildTimeEnv?: EnvRecord;
}

const readYamlRecord = async (path: string, required: boolean): Promise<ConfigRecord> => {
  let text: string;
  try {
    text = await readFile(path, 'utf8');
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (!required && code === 'ENOENT') return {};
    throw error;
  }
  const parsed = parseYaml(text) as unknown;
  if (parsed === null || parsed === undefined) return {};
  if (!isRecord(parsed)) {
    throw new YamlConfigSourceError(`config file is not a mapping: ${path}`);
  }
  return parsed;
};

/**
 * The real `ConfigSource`: base + landscape overlay YAML read from disk, plus
 * runtime `process.env` and an optional build-time injected env map. A missing
 * overlay file is treated as an empty overlay; a missing base file, or a file
 * that is not a YAML mapping, is an error.
 */
export class YamlConfigSource implements ConfigSource {
  private readonly dir: string;
  private readonly baseFile: string;
  private readonly overlayFile: (landscape: string) => string;
  private readonly env: EnvRecord;
  private readonly buildTime: EnvRecord;

  constructor(options: YamlConfigSourceOptions) {
    this.dir = options.dir;
    this.baseFile = options.baseFile ?? 'config.yaml';
    this.overlayFile = options.overlayFile ?? (landscape => `${landscape}.config.yaml`);
    this.env = options.env ?? process.env;
    this.buildTime = options.buildTimeEnv ?? {};
  }

  base(): Promise<ConfigRecord> {
    return readYamlRecord(join(this.dir, this.baseFile), true);
  }

  overlay(landscape: string): Promise<ConfigRecord> {
    return readYamlRecord(join(this.dir, this.overlayFile(landscape)), false);
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.buildTime;
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.env;
  }
}
