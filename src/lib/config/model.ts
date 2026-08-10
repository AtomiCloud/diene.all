/** The one normalized configuration model consumed by linting and releasing. */
export type ReleaseLevel = 'major' | 'minor' | 'patch' | false;

interface Vae {
  readonly verb: string;
  readonly application: string;
  readonly example: string;
}

interface ScopeRule {
  readonly desc: string;
  readonly release: ReleaseLevel;
}

export interface CommitType {
  readonly type: string;
  readonly desc: string;
  readonly section?: string;
  readonly vae?: Vae;
  readonly scopes: Readonly<Record<string, ScopeRule>>;
}

interface SpecialScope {
  readonly desc: string;
  readonly release: ReleaseLevel;
}

interface HeaderLintRules {
  readonly maxLength: number;
  readonly minLength: number;
  readonly forbiddenWords: readonly string[];
  readonly forbidTrailingPunctuation: boolean;
}

interface BodyLintRules {
  readonly maxLineLength: number;
  readonly minLengthWhenPresent: number;
  readonly requireBlankSecondLine: boolean;
}

type IgnoredCommitKind = 'merge' | 'revert' | 'fixup' | 'fixup-amend' | 'squash';

interface LintConfig {
  readonly header: HeaderLintRules;
  readonly body: BodyLintRules;
  readonly ignore: readonly IgnoredCommitKind[];
}

interface ConventionsConfig {
  readonly path: string;
  readonly template: string;
}

interface ChangelogConfig {
  readonly path: string;
  readonly title: string;
}

export interface PrepareHook {
  readonly phase: 'beforeWrite' | 'afterWrite';
  readonly command: string;
}

interface HooksConfig {
  readonly prepare: readonly PrepareHook[];
  readonly success: readonly string[];
}

type GitHubConfig =
  | false
  | {
      readonly enabled: true;
      readonly successComment: string;
      readonly releasedLabels: readonly string[];
    };

interface CommitConfig {
  readonly message: string;
  readonly assets: readonly string[];
}

interface ReleaseConfig {
  readonly branches: readonly string[];
  readonly tagFormat: string;
  readonly changelog: ChangelogConfig;
  readonly commit: CommitConfig;
  readonly github: GitHubConfig;
  readonly hooks: HooksConfig;
}

export interface ReleaserConfig {
  readonly schemaVersion: 2;
  readonly types: readonly CommitType[];
  readonly specialScopes: Readonly<Record<string, SpecialScope>>;
  readonly keywords: readonly string[];
  readonly lint: LintConfig;
  readonly conventions: ConventionsConfig;
  readonly release: ReleaseConfig;
}
