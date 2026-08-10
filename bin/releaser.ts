#!/usr/bin/env bun
import { Command, CommanderError } from 'commander';
import pkg from '../package.json' with { type: 'json' };
import { ChangelogController } from '../src/adapters/cli/changelog-controller';
import { ConventionsController } from '../src/adapters/cli/conventions-controller';
import { LintCommitController } from '../src/adapters/cli/lint-commit-controller';
import { MigrateController } from '../src/adapters/cli/migrate-controller';
import { NextController } from '../src/adapters/cli/next-controller';
import { ReleaseController } from '../src/adapters/cli/release-controller';
import { YamlConfigRepository } from '../src/adapters/config/yaml-config-repository';
import { BunFileSystem } from '../src/adapters/filesystem/bun-filesystem';
import { GitCli } from '../src/adapters/git/git-cli';
import { GitHubApi } from '../src/adapters/github/github-api';
import { BunHookRunner } from '../src/adapters/process/bun-hook-runner';
import { ConsoleIo, type ICliIo } from '../src/adapters/terminal/console-io';
import { CommitLinter } from '../src/lib/commits/linter';
import { MigrationService } from '../src/lib/migration/migration-service';
import { ConventionsService } from '../src/lib/release/conventions-service';
import { HookTemplate } from '../src/lib/release/hook-template';
import { NotesService } from '../src/lib/release/notes-service';
import type { IClock, IConfigRepository, IFileSystem, IGit, IGitHub, IHookRunner } from '../src/lib/release/ports';
import { ReleaseService } from '../src/lib/release/release-service';
import { VersionService } from '../src/lib/release/version-service';

const BINARY_NAME = 'releaser';
const DESCRIPTION = 'Offline-first conventional release and commit-lint automation';

export interface CliWorld {
  readonly io: ICliIo;
  readonly files: IFileSystem;
  readonly configs: IConfigRepository;
  readonly git: IGit;
  readonly hooks: IHookRunner;
  readonly github: IGitHub;
  readonly clock: IClock;
}

export function createProgram(): Command {
  return new Command()
    .name(BINARY_NAME)
    .description(DESCRIPTION)
    .version(pkg.version, '-v, --version', 'print the CLI version')
    .showHelpAfterError()
    .exitOverride();
}

export function buildWorld(
  cwd = process.cwd(),
  env: Readonly<Record<string, string | undefined>> = process.env,
): CliWorld {
  const files = new BunFileSystem(cwd);
  return {
    io: new ConsoleIo(),
    files,
    configs: new YamlConfigRepository(files),
    git: new GitCli(cwd, env.GITHUB_TOKEN),
    hooks: new BunHookRunner(cwd, env),
    github: new GitHubApi(env.GITHUB_TOKEN),
    clock: { today: () => new Date().toISOString().slice(0, 10) },
  };
}

export function registerDomain(program: Command, world: CliWorld): void {
  const releases = new ReleaseService(
    world.configs,
    world.files,
    world.git,
    world.hooks,
    world.github,
    new VersionService(),
    new NotesService(),
    new ConventionsService(),
    new HookTemplate(),
    world.clock,
  );
  const migration = new MigrationService(world.configs, world.files);
  new ReleaseController(releases, world.io).register(program);
  new LintCommitController(world.configs, world.files, new CommitLinter(), world.io).register(program);
  new NextController(releases, world.io).register(program);
  new ChangelogController(releases, world.io).register(program);
  new ConventionsController(releases, world.io).register(program);
  new MigrateController(migration, world.io).register(program);
}

async function execute(argv: string[], world = buildWorld()): Promise<void> {
  const program = createProgram();
  registerDomain(program, world);
  try {
    await program.parseAsync(argv);
  } catch (error) {
    if (error instanceof CommanderError) {
      world.io.setExitCode(error.exitCode);
      return;
    }
    world.io.writeError(`${error instanceof Error ? error.message : String(error)}\n`);
    world.io.setExitCode(1);
  }
}

if (import.meta.main) await execute(process.argv);
