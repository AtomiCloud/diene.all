import type { RawCommit } from '../../src/lib/commits/model';
import type { ReleaserConfig } from '../../src/lib/config/model';
import type {
  GitHubReleaseRequest,
  IClock,
  IConfigRepository,
  IFileSystem,
  IGit,
  IGitHub,
  IHookRunner,
  LoadedConfig,
} from '../../src/lib/release/ports';
import type { ICliIo } from '../../src/adapters/terminal/console-io';

export const TEST_CONFIG: ReleaserConfig = {
  schemaVersion: 2,
  types: [
    {
      type: 'feat',
      desc: 'Features',
      section: '✨ Features ✨',
      vae: { verb: 'add', application: '<title>', example: 'feat: add a capability' },
      scopes: {
        default: { desc: 'Feature', release: 'minor' },
        api: { desc: 'API feature', release: 'minor' },
      },
    },
    {
      type: 'fix',
      desc: 'Fixes',
      section: '🐛 Bug Fixes 🐛',
      scopes: { default: { desc: 'Fix', release: 'patch' } },
    },
    {
      type: 'docs',
      desc: 'Documentation',
      scopes: { default: { desc: 'Docs', release: false } },
    },
  ],
  specialScopes: { 'no-release': { desc: 'No release', release: false } },
  keywords: ['BREAKING CHANGE', 'BREAKING CHANGES', 'BREAKING'],
  lint: {
    header: { maxLength: 72, minLength: 5, forbiddenWords: ['WIP'], forbidTrailingPunctuation: true },
    body: { maxLineLength: 80, minLengthWhenPresent: 20, requireBlankSecondLine: true },
    ignore: ['merge', 'revert', 'fixup', 'fixup-amend', 'squash'],
  },
  conventions: {
    path: 'docs/developer/CommitConventions.md',
    template: '# Commit conventions\n\nCONVENTION_DOCS_PLACEHOLDER\n',
  },
  release: {
    branches: ['main'],
    tagFormat: 'v${version}',
    changelog: { path: 'Changelog.md', title: '# Changelog' },
    commit: {
      message: 'release: ${version}\n\n${notes}',
      assets: ['Changelog.md', 'docs/developer/CommitConventions.md'],
    },
    github: false,
    hooks: { prepare: [], success: [] },
  },
};

export class MemoryFileSystem implements IFileSystem {
  readonly values: Map<string, string>;

  constructor(initial: Readonly<Record<string, string>> = {}) {
    this.values = new Map(Object.entries(initial));
  }

  async readText(path: string): Promise<string> {
    const value = this.values.get(path);
    if (value === undefined) throw new Error(`file not found: ${path}`);
    return value;
  }

  async readTextIfExists(path: string): Promise<string | null> {
    return this.values.get(path) ?? null;
  }

  async writeAtomic(path: string, content: string): Promise<void> {
    this.values.set(path, content);
  }

  async exists(path: string): Promise<boolean> {
    return this.values.has(path);
  }

  async remove(path: string): Promise<void> {
    this.values.delete(path);
  }

  async hashIfExists(path: string): Promise<string | null> {
    const value = this.values.get(path);
    if (value === undefined) return null;
    const hasher = new Bun.CryptoHasher('sha256');
    hasher.update(value);
    return hasher.digest('hex');
  }

  matchesAny(path: string, patterns: readonly string[]): boolean {
    return patterns.some(pattern => pattern === path || new Bun.Glob(pattern).match(path));
  }
}

export class FakeConfigRepository implements IConfigRepository {
  written: ReleaserConfig | null = null;

  constructor(readonly loaded: LoadedConfig) {}

  async load(_path: string): Promise<LoadedConfig> {
    return this.loaded;
  }

  async writeCanonical(_path: string, config: ReleaserConfig): Promise<void> {
    this.written = config;
  }
}

export class FakeGit implements IGit {
  readonly calls: string[] = [];
  branch = 'main';
  clean = true;
  tags: string[] = [];
  commits: RawCommit[] = [];
  changed: string[] = ['Changelog.md', 'docs/developer/CommitConventions.md'];
  repository = 'https://github.com/AtomiCloud/example';
  githubSlug: string | null = 'AtomiCloud/example';
  committedMessage = '';
  validatedTags: string[] = [];
  tagValidationError: Error | null = null;

  async currentBranch(): Promise<string> {
    return this.branch;
  }

  async isClean(): Promise<boolean> {
    return this.clean;
  }

  async reachableTags(): Promise<readonly string[]> {
    return this.tags;
  }

  async commitsSince(_tag: string | null): Promise<readonly RawCommit[]> {
    return this.commits;
  }

  async repositoryUrl(): Promise<string | null> {
    return this.repository;
  }

  async githubRepository(): Promise<string | null> {
    return this.githubSlug;
  }

  async validateTag(tag: string): Promise<void> {
    this.validatedTags.push(tag);
    if (this.tagValidationError !== null) throw this.tagValidationError;
  }

  async changedFiles(): Promise<readonly string[]> {
    return this.changed;
  }

  async stage(paths: readonly string[]): Promise<void> {
    this.calls.push(`stage:${paths.join(',')}`);
  }

  async commit(message: string): Promise<void> {
    this.committedMessage = message;
    this.calls.push('commit');
  }

  async createTag(tag: string): Promise<void> {
    this.calls.push(`tag:${tag}`);
  }

  async push(branch: string, tag: string): Promise<void> {
    this.calls.push(`push:${branch}:${tag}`);
  }
}

export class FakeHookRunner implements IHookRunner {
  readonly commands: string[] = [];
  failure: Error | null = null;

  async run(command: string): Promise<void> {
    this.commands.push(command);
    if (this.failure !== null) throw this.failure;
  }
}

export class FakeGitHub implements IGitHub {
  readonly requests: GitHubReleaseRequest[] = [];

  async publishRelease(request: GitHubReleaseRequest): Promise<void> {
    this.requests.push(request);
  }
}

export class FakeClock implements IClock {
  constructor(private readonly date = '2026-07-22') {}

  today(): string {
    return this.date;
  }
}

export interface CapturedIo extends ICliIo {
  readonly out: string[];
  readonly err: string[];
  readonly codes: number[];
}

export function captureIo(): CapturedIo {
  const out: string[] = [];
  const err: string[] = [];
  const codes: number[] = [];
  return {
    out,
    err,
    codes,
    write: text => out.push(text),
    writeError: text => err.push(text),
    setExitCode: code => codes.push(code),
  };
}

export function loadedConfig(config: ReleaserConfig = TEST_CONFIG, sourceVersion: 1 | 2 = 2): LoadedConfig {
  return { config, sourceVersion, warnings: [], legacyGitlintPath: '.gitlint' };
}
