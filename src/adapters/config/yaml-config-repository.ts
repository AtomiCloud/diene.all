import type { ReleaserConfig } from '../../lib/config/model';
import { detectSchemaVersion, parseCanonicalV2 } from '../../lib/config/schema';
import { translateV1 } from '../../lib/config/translator';
import { ConfigError } from '../../lib/errors';
import type { IConfigRepository, IFileSystem, LoadedConfig } from '../../lib/release/ports';

export class YamlConfigRepository implements IConfigRepository {
  constructor(private readonly files: IFileSystem) {}

  async load(path: string): Promise<LoadedConfig> {
    let raw: unknown;
    try {
      raw = Bun.YAML.parse(await this.files.readText(path));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new ConfigError(`failed to read YAML configuration "${path}": ${message}`);
    }
    const sourceVersion = detectSchemaVersion(raw);
    if (sourceVersion === 2) {
      return {
        config: parseCanonicalV2(raw),
        sourceVersion,
        warnings: [],
        legacyGitlintPath: '.gitlint',
      };
    }
    const translated = translateV1(raw);
    return {
      config: translated.config,
      sourceVersion,
      warnings: translated.warnings,
      legacyGitlintPath: translated.gitlintPath,
    };
  }

  async writeCanonical(path: string, config: ReleaserConfig): Promise<void> {
    const yaml = Bun.YAML.stringify(config, null, 2);
    await this.files.writeAtomic(path, `${yaml.trimEnd()}\n`);
  }
}
