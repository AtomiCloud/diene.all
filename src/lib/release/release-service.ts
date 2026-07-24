import type { RawCommit } from '../commits/model';
import type { ReleaserConfig } from '../config/model';
import { ReleaseError, ReleaserError } from '../errors';
import type { ConventionsService } from './conventions-service';
import type { HookTemplate } from './hook-template';
import type { NotesService } from './notes-service';
import type { IClock, IConfigRepository, IFileSystem, IGit, IGitHub, IHookRunner, LoadedConfig } from './ports';
import type { ReleaseTag, VersionService } from './version-service';

export interface ReleasePreview {
  readonly config: ReleaserConfig;
  readonly sourceVersion: 1 | 2;
  readonly warnings: readonly string[];
  readonly version: string;
  readonly tag: string;
  readonly previousTag: string | null;
  readonly notes: string;
  readonly commits: readonly RawCommit[];
}

const LOCK_FILES = ['bun.lock', 'bun.lockb', 'package-lock.json', 'pnpm-lock.yaml', 'yarn.lock'] as const;
const SKIP_CI = /\[(?:skip ci|ci skip)\]/i;

async function runPhase<T>(phase: string, action: () => Promise<T>): Promise<T> {
  try {
    return await action();
  } catch (error) {
    if (error instanceof ReleaseError && error.phase === phase) throw error;
    const message = error instanceof Error ? error.message : String(error);
    throw new ReleaseError(`${phase} failed: ${message}`, phase);
  }
}

function assertAllowedBranch(config: ReleaserConfig, branch: string): void {
  if (!config.release.branches.includes(branch)) {
    throw new ReleaseError(
      `current branch "${branch}" is not allowed (expected one of: ${config.release.branches.join(', ')})`,
      'precondition',
    );
  }
}

function prependNotes(existing: string | null, title: string, notes: string): string {
  if (existing === null || existing.trim().length === 0) return `${title.trimEnd()}\n\n${notes.trimEnd()}\n`;
  const normalized = existing.replaceAll('\r\n', '\n');
  const heading = /^## /m.exec(normalized);
  if (heading === null || heading.index === undefined) {
    return `${normalized.trimEnd()}\n\n${notes.trimEnd()}\n`;
  }
  const preamble = normalized.slice(0, heading.index).trimEnd();
  const releases = normalized.slice(heading.index).trimStart();
  if (preamble.length === 0) return `${notes.trimEnd()}\n\n${releases}`;
  return `${preamble}\n\n${notes.trimEnd()}\n\n${releases}`;
}

async function lockHashes(fileSystem: IFileSystem): Promise<Readonly<Record<string, string | null>>> {
  const pairs = await Promise.all(LOCK_FILES.map(async path => [path, await fileSystem.hashIfExists(path)] as const));
  return Object.fromEntries(pairs);
}

function assertLocksUnchanged(
  before: Readonly<Record<string, string | null>>,
  after: Readonly<Record<string, string | null>>,
): void {
  for (const path of LOCK_FILES) {
    if (before[path] !== after[path]) throw new ReleaseError(`lockfile changed unexpectedly: ${path}`, 'asset-fence');
  }
}

function assertAssetFence(fileSystem: IFileSystem, changedFiles: readonly string[], assets: readonly string[]): void {
  const unexpected = changedFiles.filter(path => !fileSystem.matchesAny(path, assets));
  if (unexpected.length > 0) {
    throw new ReleaseError(
      `hook or generator changed files outside configured assets: ${unexpected.join(', ')}`,
      'asset-fence',
    );
  }
}

function latestVersion(latest: ReleaseTag | null): ReleaseTag | null {
  return latest;
}

export class ReleaseService {
  constructor(
    private readonly configs: IConfigRepository,
    private readonly files: IFileSystem,
    private readonly git: IGit,
    private readonly hooks: IHookRunner,
    private readonly github: IGitHub,
    private readonly versions: VersionService,
    private readonly notes: NotesService,
    private readonly conventions: ConventionsService,
    private readonly templates: HookTemplate,
    private readonly clock: IClock,
  ) {}

  async preview(configPath = 'atomi_release.yaml'): Promise<ReleasePreview | null> {
    const loaded = await this.configs.load(configPath);
    const branch = await this.git.currentBranch();
    assertAllowedBranch(loaded.config, branch);
    const latest = latestVersion(
      this.versions.latestTag(await this.git.reachableTags(), loaded.config.release.tagFormat),
    );
    const commits = await this.git.commitsSince(latest?.tag ?? null);
    const decision = this.versions.analyze(loaded.config, latest?.version ?? null, commits);
    if (decision === null) return null;
    const version = this.versions.format(decision.version);
    const tag = this.versions.formatTag(loaded.config.release.tagFormat, decision.version);
    await this.git.validateTag(tag);
    const notes = this.notes.render({
      config: loaded.config,
      version,
      previousTag: latest?.tag ?? null,
      newTag: tag,
      commits,
      repositoryUrl: await this.git.repositoryUrl(),
      date: this.clock.today(),
    });
    return {
      config: loaded.config,
      sourceVersion: loaded.sourceVersion,
      warnings: loaded.warnings,
      version,
      tag,
      previousTag: latest?.tag ?? null,
      notes,
      commits,
    };
  }

  async release(configPath = 'atomi_release.yaml', dryRun = false): Promise<ReleasePreview | null> {
    if (!(await this.git.isClean())) throw new ReleaseError('working tree must be clean', 'precondition');
    const preview = await this.preview(configPath);
    if (preview === null || dryRun) return preview;
    const beforeLocks = await lockHashes(this.files);

    for (const hook of preview.config.release.hooks.prepare.filter(candidate => candidate.phase === 'beforeWrite')) {
      await runPhase('prepare:beforeWrite', () =>
        this.hooks.run(this.templates.renderCommand(hook.command, preview.version, preview.notes)),
      );
    }

    await runPhase('write:conventions', () =>
      this.files.writeAtomic(preview.config.conventions.path, this.conventions.render(preview.config)),
    );
    await runPhase('write:changelog', async () => {
      const current = await this.files.readTextIfExists(preview.config.release.changelog.path);
      await this.files.writeAtomic(
        preview.config.release.changelog.path,
        prependNotes(current, preview.config.release.changelog.title, preview.notes),
      );
    });

    for (const hook of preview.config.release.hooks.prepare.filter(candidate => candidate.phase === 'afterWrite')) {
      await runPhase('prepare:afterWrite', () =>
        this.hooks.run(this.templates.renderCommand(hook.command, preview.version, preview.notes)),
      );
    }

    assertLocksUnchanged(beforeLocks, await lockHashes(this.files));
    const changedFiles = await runPhase('asset-fence', () => this.git.changedFiles());
    assertAssetFence(this.files, changedFiles, preview.config.release.commit.assets);
    if (changedFiles.length === 0)
      throw new ReleaseError('release produced no configured asset changes', 'asset-fence');

    const message = this.templates.renderText(preview.config.release.commit.message, preview.version, preview.notes);
    if (SKIP_CI.test(message))
      throw new ReleaseError('release commit message contains a forbidden skip-CI token', 'commit');
    await runPhase('stage', () => this.git.stage(preview.config.release.commit.assets));
    await runPhase('commit', () => this.git.commit(message));
    await runPhase('post-commit-fence', async () => {
      if (!(await this.git.isClean())) {
        throw new ReleaseError('working tree is dirty after the release commit', 'post-commit-fence');
      }
    });
    await runPhase('tag', () => this.git.createTag(preview.tag));
    const branch = await this.git.currentBranch();
    await runPhase('push', () => this.git.push(branch, preview.tag));

    if (preview.config.release.github !== false) {
      const repository = await this.git.githubRepository();
      if (repository === null)
        throw new ReleaseError('GitHub release is enabled but origin is not a GitHub repository', 'github');
      await runPhase('github', () =>
        this.github.publishRelease({
          repository,
          tag: preview.tag,
          version: preview.version,
          notes: preview.notes,
          commits: preview.commits,
          successComment: this.templates.renderText(
            preview.config.release.github === false ? '' : preview.config.release.github.successComment,
            preview.version,
            preview.notes,
          ),
          releasedLabels: preview.config.release.github === false ? [] : preview.config.release.github.releasedLabels,
        }),
      );
    }

    for (const hook of preview.config.release.hooks.success) {
      await runPhase('success-hook', () =>
        this.hooks.run(this.templates.renderCommand(hook, preview.version, preview.notes)),
      );
    }
    if (!(await this.git.isClean())) throw new ReleaseError('working tree is dirty after release', 'postcondition');
    return preview;
  }

  async writeConventions(configPath = 'atomi_release.yaml'): Promise<LoadedConfig> {
    const loaded = await this.configs.load(configPath);
    await this.files.writeAtomic(loaded.config.conventions.path, this.conventions.render(loaded.config));
    return loaded;
  }
}

export function userMessage(error: unknown): string {
  if (error instanceof ReleaserError) return error.message;
  if (error instanceof Error) return error.message;
  return String(error);
}
