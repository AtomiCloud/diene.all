import { afterEach, describe, expect, it } from 'bun:test';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';
import { commitAll, run, scratchRepository } from '../helpers/scratch-repo';
import { configuredDriver } from './driver';

const roots: string[] = [];
const driver = configuredDriver();

function v2Config(type = 'feat', release = 'minor'): string {
  return `
schemaVersion: 2
types:
  - type: ${type}
    desc: Test type
    section: Test changes
    scopes:
      default: { desc: Test change, release: ${release} }
conventions:
  path: CommitConventions.md
  template: "# Conventions\\n\\nCONVENTION_DOCS_PLACEHOLDER\\n"
release:
  branches: [main]
  changelog: { path: Changelog.md, title: "# Changelog" }
  commit:
    message: "release: \${version}\\n\\n\${notes}"
    assets: [Changelog.md, CommitConventions.md]
  github: false
`;
}

function hookConfig(): string {
  return `
schemaVersion: 2
types:
  - type: feat
    desc: Test type
    section: Test changes
    scopes:
      default: { desc: Test change, release: minor }
conventions:
  path: CommitConventions.md
  template: "# Conventions\\n\\nCONVENTION_DOCS_PLACEHOLDER\\n"
release:
  branches: [main]
  changelog: { path: Changelog.md, title: "# Changelog" }
  commit:
    message: "release: \${version}\\n\\n\${notes}"
    assets: [Changelog.md, CommitConventions.md, HookAsset.txt]
  github: false
  hooks:
    prepare:
      - phase: beforeWrite
        command: "echo before > HookAsset.txt"
      - phase: afterWrite
        command: "echo after >> HookAsset.txt"
    success:
      - "echo done > .git/releaser-success.marker"
`;
}

async function repository(message = 'feat: add release'): Promise<{ readonly root: string; readonly remote: string }> {
  const scratch = await scratchRepository();
  roots.push(scratch.root, scratch.remote);
  await Bun.write(join(scratch.root, 'atomi_release.yaml'), v2Config());
  await Bun.write(join(scratch.root, 'Changelog.md'), '# Changelog\n');
  await Bun.write(join(scratch.root, 'CommitConventions.md'), '# old\n');
  await Bun.write(join(scratch.root, 'package.json'), '{"name":"fixture","version":"1.0.0"}\n');
  await Bun.write(join(scratch.root, 'bun.lock'), 'locked\n');
  await commitAll(scratch.root, message);
  await run(['git', 'push', '-q', '-u', 'origin', 'main'], scratch.root);
  return scratch;
}

afterEach(async () => {
  await Promise.all(roots.splice(0).map(path => rm(path, { recursive: true })));
});

describe(`releaser SIT (${process.env.SIT_DRIVER === 'binary' ? 'binary' : 'in-process'})`, () => {
  it('should report version 1.0.0 and list exactly the six domain commands', async () => {
    // Act
    const version = await driver.run(['--version'], process.cwd());
    const help = await driver.run(['--help'], process.cwd());

    // Assert
    expect(version).toMatchObject({ code: 0, out: '1.0.0\n' });
    for (const command of ['release', 'lint-commit', 'next', 'changelog', 'conventions', 'migrate']) {
      expect(help.out).toContain(command);
    }
    expect(help.out).not.toContain('seed');
  });

  it('should keep release --dry-run and changelog byte-side-effect free', async () => {
    // Arrange
    const scratch = await repository();
    const beforeStatus = await run(['git', 'status', '--porcelain'], scratch.root);
    const beforeLock = await Bun.file(join(scratch.root, 'bun.lock')).text();

    // Act
    const dryRun = await driver.run(['release', '--dry-run'], scratch.root);
    const changelog = await driver.run(['changelog'], scratch.root);

    // Assert
    expect(dryRun.code).toBe(0);
    expect(dryRun.out).toStartWith('1.0.0\n\n## 1.0.0');
    expect(changelog.out).toStartWith('## 1.0.0');
    expect(await run(['git', 'status', '--porcelain'], scratch.root)).toBe(beforeStatus);
    expect(await Bun.file(join(scratch.root, 'bun.lock')).text()).toBe(beforeLock);
  });

  it('should perform a complete local release with exact commit, tag, push, and no loop', async () => {
    // Arrange
    const scratch = await repository();

    // Act
    const release = await driver.run(['release'], scratch.root);
    const next = await driver.run(['next'], scratch.root);

    // Assert
    expect(release).toMatchObject({ code: 0, out: 'released 1.0.0\n' });
    expect((await run(['git', 'tag', '--list'], scratch.remote)).trim()).toBe('v1.0.0');
    expect(await run(['git', 'log', '-1', '--format=%s'], scratch.remote)).toBe('release: 1.0.0\n');
    expect(next).toMatchObject({ code: 2, err: 'no release necessary\n' });
  });

  it('should run ordered prepare hooks and a success hook, then leave a clean immutable tree', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    await Bun.write(join(scratch.root, 'atomi_release.yaml'), hookConfig());
    await Bun.write(join(scratch.root, 'Changelog.md'), '# Changelog\n');
    await Bun.write(join(scratch.root, 'CommitConventions.md'), '# old\n');
    await Bun.write(join(scratch.root, 'package.json'), '{"name":"fixture","version":"1.0.0"}\n');
    await Bun.write(join(scratch.root, 'bun.lock'), 'locked\n');
    await commitAll(scratch.root, 'feat: add release');
    await run(['git', 'push', '-q', '-u', 'origin', 'main'], scratch.root);
    const beforePackage = await Bun.file(join(scratch.root, 'package.json')).text();
    const beforeLock = await Bun.file(join(scratch.root, 'bun.lock')).text();

    // Act
    const release = await driver.run(['release'], scratch.root);

    // Assert
    expect(release).toMatchObject({ code: 0, out: 'released 1.0.0\n' });
    // Prepare hooks ran in order: beforeWrite created the asset, afterWrite appended to it.
    expect(await Bun.file(join(scratch.root, 'HookAsset.txt')).text()).toBe('before\nafter\n');
    // Success hook executed; it wrote under .git so the working tree stays clean.
    expect(await Bun.file(join(scratch.root, '.git', 'releaser-success.marker')).text()).toBe('done\n');
    // Generated documents contain their expected content.
    const changelog = await Bun.file(join(scratch.root, 'Changelog.md')).text();
    expect(changelog).toContain('# Changelog');
    expect(changelog).toContain('## 1.0.0');
    const conventions = await Bun.file(join(scratch.root, 'CommitConventions.md')).text();
    expect(conventions).toContain('# Conventions');
    expect(conventions).toContain('## Types');
    // The package manifest and lockfile are byte-identical (M1–M3): the tool never touches them.
    expect(await Bun.file(join(scratch.root, 'package.json')).text()).toBe(beforePackage);
    expect(await Bun.file(join(scratch.root, 'bun.lock')).text()).toBe(beforeLock);
    // The working tree is clean, and the hook-produced asset landed in the release commit.
    expect((await run(['git', 'status', '--porcelain'], scratch.root)).trim()).toBe('');
    expect(await run(['git', 'show', '--name-only', '--format=', 'HEAD'], scratch.root)).toContain('HookAsset.txt');
  });

  it('should lint valid and invalid commit messages with stable diagnostics', async () => {
    // Arrange
    const scratch = await repository();
    await Bun.write(join(scratch.root, 'valid.txt'), 'feat: add a release capability\n');
    await Bun.write(join(scratch.root, 'invalid.txt'), 'WIP bad.\n');

    // Act
    const valid = await driver.run(['lint-commit', 'valid.txt'], scratch.root);
    const invalid = await driver.run(['lint-commit', 'invalid.txt'], scratch.root);

    // Assert
    expect(valid).toMatchObject({ code: 0, out: '', err: '' });
    expect(invalid.code).toBe(1);
    expect(invalid.err).toContain('invalid.txt:1:');
  });

  it('should print next and return exit 2 when no commit requests a release', async () => {
    // Arrange
    const release = await repository();
    const none = await repository('docs: update documentation');

    // Act / Assert
    expect(await driver.run(['next'], release.root)).toMatchObject({ code: 0, out: '1.0.0\n' });
    expect(await driver.run(['next'], none.root)).toMatchObject({ code: 2, err: 'no release necessary\n' });
  });

  it('should make conventions the only changed path', async () => {
    // Arrange
    const scratch = await repository();

    // Act
    const actual = await driver.run(['conventions'], scratch.root);

    // Assert
    expect(actual).toMatchObject({ code: 0, out: 'wrote CommitConventions.md\n' });
    expect((await run(['git', 'status', '--porcelain'], scratch.root)).trim()).toBe('M CommitConventions.md');
  });

  it('should migrate v1, remove legacy files, and remain byte-idempotent', async () => {
    // Arrange
    const scratch = await scratchRepository();
    roots.push(scratch.root, scratch.remote);
    const legacy = `
conventionMarkdown: { path: CommitConventions.md, template: CONVENTION_DOCS_PLACEHOLDER }
gitlint: .gitlint
branches: [main]
types:
  - type: feat
    desc: Features
    scopes:
      default: { desc: Feature, release: minor }
plugins:
  - module: '@semantic-release/changelog'
  - module: '@semantic-release/git'
    config:
      message: "release: \${nextRelease.version}\\n\\n\${nextRelease.notes}\\n\\n[skip ci]\\n\\nSigned"
      assets: [Changelog.md]
`;
    await Bun.write(join(scratch.root, 'atomi_release.yaml'), legacy);
    await Bun.write(join(scratch.root, '.gitlint'), 'legacy');
    await Bun.write(join(scratch.root, '.releaserc.yaml'), 'generated');

    // Act
    const first = await driver.run(['migrate'], scratch.root);
    const migrated = await Bun.file(join(scratch.root, 'atomi_release.yaml')).text();
    const second = await driver.run(['migrate'], scratch.root);

    // Assert
    expect(first.out).toContain('migrated');
    expect(first.out).toContain('normalizations:\n- removed legacy [skip ci] token');
    expect(second.out).toStartWith('already v2');
    expect(second.out).not.toContain('normalizations:');
    expect(Bun.YAML.parse(migrated)).toMatchObject({
      release: {
        commit: {
          message: 'release: ${version}\n\n${notes}\n\n\n\nSigned',
        },
      },
    });
    expect(await Bun.file(join(scratch.root, 'atomi_release.yaml')).text()).toBe(migrated);
    expect(await Bun.file(join(scratch.root, '.gitlint')).exists()).toBe(false);
    expect(await Bun.file(join(scratch.root, '.releaserc.yaml')).exists()).toBe(false);
  });

  it('should fail unknown legacy modules and wrong branches loudly', async () => {
    // Arrange
    const scratch = await repository();
    await run(['git', 'branch', '-m', 'wrong'], scratch.root);
    const wrong = await driver.run(['next'], scratch.root);
    const config = await Bun.file(join(scratch.root, 'atomi_release.yaml')).text();
    await Bun.write(
      join(scratch.root, 'atomi_release.yaml'),
      config.replace('schemaVersion: 2', 'branches: [main]\nplugins: [{ module: "@semantic-release/npm" }]'),
    );

    // Act
    const unknown = await driver.run(['migrate'], scratch.root);

    // Assert
    expect(wrong.code).toBe(1);
    expect(wrong.err).toContain('not allowed');
    expect(unknown.code).toBe(1);
  });

  it('should reject an invalid rendered tag before every release mutation surface', async () => {
    // Arrange
    const scratch = await repository();
    const configPath = join(scratch.root, 'atomi_release.yaml');
    const config = await Bun.file(configPath).text();
    await Bun.write(configPath, config.replace('branches: [main]', 'branches: [main]\n  tagFormat: "bad..${version}"'));
    await commitAll(scratch.root, 'feat: configure invalid tag');
    const beforeChangelog = await Bun.file(join(scratch.root, 'Changelog.md')).text();

    // Act
    const next = await driver.run(['next'], scratch.root);
    const changelog = await driver.run(['changelog'], scratch.root);
    const dryRun = await driver.run(['release', '--dry-run'], scratch.root);
    const release = await driver.run(['release'], scratch.root);

    // Assert
    for (const result of [next, changelog, dryRun, release]) {
      expect(result.code).toBe(1);
      expect(result.err).toContain('check-ref-format');
    }
    expect(await Bun.file(join(scratch.root, 'Changelog.md')).text()).toBe(beforeChangelog);
    expect(await run(['git', 'status', '--porcelain'], scratch.root)).toBe('');
    expect(await run(['git', 'tag', '--list'], scratch.root)).toBe('');
  });
});
