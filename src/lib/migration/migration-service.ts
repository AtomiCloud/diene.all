import type { IConfigRepository, IFileSystem } from '../release/ports';

const CHECKLIST = [
  'replace Nix sg/Gitlint packages with releaser',
  'replace a-enforce-gitlint and a-gitlint with the a-releaser-commit commit-msg hook',
  'simplify release.sh to invoke releaser release',
  'remove cache-npm from the release workflow',
  'remove the node_modules clearing dance',
  'remove git checkout HEAD -- package.json from bump.sh',
] as const;

export interface MigrationResult {
  readonly alreadyV2: boolean;
  readonly removed: readonly string[];
  readonly output: string;
}

export class MigrationService {
  constructor(
    private readonly configs: IConfigRepository,
    private readonly files: IFileSystem,
  ) {}

  async migrate(configPath = 'atomi_release.yaml'): Promise<MigrationResult> {
    const loaded = await this.configs.load(configPath);
    if (loaded.sourceVersion === 1) await this.configs.writeCanonical(configPath, loaded.config);
    const candidates = [...new Set([loaded.legacyGitlintPath, '.releaserc.yaml'])];
    const removed: string[] = [];
    for (const path of candidates) {
      if (await this.files.exists(path)) {
        await this.files.remove(path);
        removed.push(path);
      }
    }
    const lines = [
      loaded.sourceVersion === 2 ? 'already v2' : 'migrated atomi_release.yaml to schemaVersion 2',
      `removed legacy files: ${removed.length === 0 ? 'none' : removed.join(', ')}`,
      ...(loaded.warnings.length === 0 ? [] : ['normalizations:', ...loaded.warnings.map(warning => `- ${warning}`)]),
      'consumer checklist:',
      ...CHECKLIST.map(item => `- ${item}`),
    ];
    return { alreadyV2: loaded.sourceVersion === 2, removed, output: `${lines.join('\n')}\n` };
  }
}
