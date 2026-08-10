/** Stable, user-facing failures emitted by the pure releaser domain. */
export class ReleaserError extends Error {
  constructor(message: string) {
    super(message);
    this.name = new.target.name;
  }
}

export class ConfigError extends ReleaserError {}

export class UnsupportedModuleError extends ConfigError {}

export class ReleaseError extends ReleaserError {
  constructor(
    message: string,
    readonly phase: string,
  ) {
    super(message);
  }
}

export class GitError extends ReleaserError {}

export class HookError extends ReleaserError {}

export class GitHubError extends ReleaserError {}
