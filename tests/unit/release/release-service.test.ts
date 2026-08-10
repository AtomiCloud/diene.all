import { describe, expect, it } from 'bun:test';
import type { ReleaserConfig } from '../../../src/lib/config/model';
import { ReleaseError } from '../../../src/lib/errors';
import { ConventionsService } from '../../../src/lib/release/conventions-service';
import { HookTemplate } from '../../../src/lib/release/hook-template';
import { NotesService } from '../../../src/lib/release/notes-service';
import { ReleaseService, userMessage } from '../../../src/lib/release/release-service';
import { VersionService } from '../../../src/lib/release/version-service';
import {
  FakeClock,
  FakeConfigRepository,
  FakeGit,
  FakeGitHub,
  FakeHookRunner,
  loadedConfig,
  MemoryFileSystem,
  TEST_CONFIG,
} from '../../helpers/fakes';

function fixture(config = TEST_CONFIG): {
  readonly subject: ReleaseService;
  readonly files: MemoryFileSystem;
  readonly git: FakeGit;
  readonly hooks: FakeHookRunner;
  readonly github: FakeGitHub;
} {
  const files = new MemoryFileSystem({ 'Changelog.md': '# Changelog\n', 'bun.lock': 'locked' });
  const git = new FakeGit();
  git.commits = [{ sha: 'a'.repeat(40), message: 'feat: add release' }];
  const hooks = new FakeHookRunner();
  const github = new FakeGitHub();
  return {
    files,
    git,
    hooks,
    github,
    subject: new ReleaseService(
      new FakeConfigRepository(loadedConfig(config)),
      files,
      git,
      hooks,
      github,
      new VersionService(),
      new NotesService(),
      new ConventionsService(),
      new HookTemplate(),
      new FakeClock(),
    ),
  };
}

describe('release service', () => {
  it('should keep dry-run pure', async () => {
    // Arrange
    const { subject, files, git } = fixture();
    const before = new Map(files.values);

    // Act
    const actual = await subject.release('atomi_release.yaml', true);

    // Assert
    expect(actual?.version).toBe('1.0.0');
    expect(files.values).toEqual(before);
    expect(git.calls).toEqual([]);
  });

  it('should execute writes, exact commit, tag, and atomic-push seam in order', async () => {
    // Arrange
    const config = {
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: {
          prepare: [
            { phase: 'beforeWrite' as const, command: './before ${version}' },
            { phase: 'afterWrite' as const, command: './after ${version}' },
          ],
          success: ['./success ${version}'],
        },
      },
    };
    const { subject, files, git, hooks } = fixture(config);

    // Act
    const actual = await subject.release();

    // Assert
    expect(actual?.version).toBe('1.0.0');
    expect(files.values.get('Changelog.md')).toContain('## 1.0.0');
    expect(files.values.get('docs/developer/CommitConventions.md')).toContain('## Types');
    expect(git.calls).toEqual([
      'stage:Changelog.md,docs/developer/CommitConventions.md',
      'commit',
      'tag:v1.0.0',
      'push:main:v1.0.0',
    ]);
    expect(git.committedMessage).toStartWith('release: 1.0.0\n\n## 1.0.0');
    expect(git.committedMessage).not.toMatch(/\[(skip ci|ci skip)\]/i);
    expect(hooks.commands).toEqual(["./before '1.0.0'", "./after '1.0.0'", "./success '1.0.0'"]);
  });

  it('should fail before staging when a hook changes an unexpected asset or lockfile', async () => {
    // Arrange
    const unexpected = fixture();
    unexpected.git.changed = ['unexpected.txt'];
    const lock = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: { prepare: [{ phase: 'beforeWrite', command: './change-lock' }], success: [] },
      },
    });
    const renamed = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        commit: {
          ...TEST_CONFIG.release.commit,
          assets: [...TEST_CONFIG.release.commit.assets, 'allowed.txt'],
        },
      },
    });
    renamed.git.changed = ['allowed.txt', 'outside.txt'];
    lock.hooks.run = async command => {
      lock.hooks.commands.push(command);
      lock.files.values.set('bun.lock', 'changed');
    };

    // Act / Assert
    await expect(unexpected.subject.release()).rejects.toThrow('outside configured assets');
    await expect(lock.subject.release()).rejects.toThrow('lockfile changed unexpectedly');
    await expect(renamed.subject.release()).rejects.toThrow('outside.txt');
    expect(unexpected.git.calls).toEqual([]);
    expect(lock.git.calls).toEqual([]);
    expect(renamed.git.calls).toEqual([]);
  });

  it('should stop before tag and push when the release commit leaves a dirty path', async () => {
    // Arrange
    const dirty = fixture();
    let cleanChecks = 0;
    dirty.git.isClean = async () => {
      cleanChecks += 1;
      return cleanChecks === 1;
    };

    // Act / Assert
    await expect(dirty.subject.release()).rejects.toThrow('dirty after the release commit');
    expect(dirty.git.calls).toEqual(['stage:Changelog.md,docs/developer/CommitConventions.md', 'commit']);
    expect(dirty.git.calls.some(call => call.startsWith('tag:') || call.startsWith('push:'))).toBe(false);
  });

  it('should reject an ambiguous hook template before invoking the hook runner', async () => {
    // Arrange
    const invalid = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: {
          prepare: [{ phase: 'beforeWrite', command: "hook '${version}" }],
          success: [],
        },
      },
    });

    // Act / Assert
    await expect(invalid.subject.release()).rejects.toThrow('unterminated');
    expect(invalid.hooks.commands).toEqual([]);
    expect(invalid.git.calls).toEqual([]);
  });

  it('should validate the rendered tag before any mutation', async () => {
    // Arrange
    const invalid = fixture({
      ...TEST_CONFIG,
      release: { ...TEST_CONFIG.release, tagFormat: 'bad..${version}' },
    });
    invalid.git.tagValidationError = new Error('invalid tag ref');
    const before = new Map(invalid.files.values);

    // Act / Assert
    await expect(invalid.subject.preview()).rejects.toThrow('invalid tag ref');
    await expect(invalid.subject.release('atomi_release.yaml', true)).rejects.toThrow('invalid tag ref');
    await expect(invalid.subject.release()).rejects.toThrow('invalid tag ref');
    expect(invalid.files.values).toEqual(before);
    expect(invalid.hooks.commands).toEqual([]);
    expect(invalid.git.calls).toEqual([]);
    expect(invalid.git.validatedTags).toEqual(['bad..1.0.0', 'bad..1.0.0', 'bad..1.0.0']);
  });

  it('should prepend notes at byte zero when the changelog has no preamble', async () => {
    // Arrange
    const release = fixture();
    release.files.values.set('Changelog.md', '## 0.9.0 (2026-01-01)\n\nold release\n');

    // Act
    await release.subject.release();

    // Assert
    const changelog = release.files.values.get('Changelog.md');
    expect(changelog).toStartWith('## 1.0.0');
    expect(changelog).toContain('## 0.9.0 (2026-01-01)\n\nold release\n');
  });

  it('should publish the configured GitHub release payload and reject a non-GitHub origin', async () => {
    const config: ReleaserConfig = {
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        github: {
          enabled: true,
          successComment: 'Released ${version}: ${notes}',
          releasedLabels: ['released', 'shipped'],
        },
      },
    };
    const published = fixture(config);

    await published.subject.release();

    expect(published.github.requests).toHaveLength(1);
    expect(published.github.requests[0]).toMatchObject({
      repository: 'AtomiCloud/example',
      tag: 'v1.0.0',
      version: '1.0.0',
      releasedLabels: ['released', 'shipped'],
    });
    expect(published.github.requests[0]?.successComment).toStartWith('Released 1.0.0: ## 1.0.0');

    const missingRepository = fixture(config);
    missingRepository.git.githubSlug = null;
    await expect(missingRepository.subject.release()).rejects.toThrow('origin is not a GitHub repository');
    expect(missingRepository.github.requests).toEqual([]);
  });

  it('should expose no-release, precondition, empty-asset, and hook failure contracts', async () => {
    const noRelease = fixture();
    noRelease.git.commits = [{ sha: 'a', message: 'docs: update guide' }];
    expect(await noRelease.subject.preview()).toBeNull();
    expect(await noRelease.subject.release()).toBeNull();

    const dirty = fixture();
    dirty.git.clean = false;
    await expect(dirty.subject.release()).rejects.toThrow('working tree must be clean');

    const empty = fixture();
    empty.git.changed = [];
    await expect(empty.subject.release()).rejects.toThrow('no configured asset changes');

    const failingHook = fixture({
      ...TEST_CONFIG,
      release: {
        ...TEST_CONFIG.release,
        hooks: { prepare: [{ phase: 'beforeWrite', command: './fail' }], success: [] },
      },
    });
    failingHook.hooks.failure = new Error('hook exploded');
    await expect(failingHook.subject.release()).rejects.toThrow('prepare:beforeWrite failed: hook exploded');
  });

  it('should write conventions independently and render safe user-facing errors', async () => {
    const release = fixture();
    const loaded = await release.subject.writeConventions('custom.yaml');

    expect(loaded.config).toBe(TEST_CONFIG);
    expect(release.files.values.get(TEST_CONFIG.conventions.path)).toContain('## Types');
    expect(userMessage(new ReleaseError('release failed', 'test'))).toBe('release failed');
    expect(userMessage(new Error('ordinary failure'))).toBe('ordinary failure');
    expect(userMessage({ reason: 'unknown' })).toBe('[object Object]');
  });
});
