export interface RawCommit {
  readonly sha: string;
  readonly message: string;
}

export interface CommitFooter {
  readonly token: string;
  readonly value: string;
}

export interface ConventionalCommit {
  readonly type: string;
  readonly scope: string | null;
  readonly breaking: boolean;
  readonly subject: string;
  readonly body: string;
  readonly footers: readonly CommitFooter[];
}

export type CommitClassification =
  | { readonly kind: 'ignored'; readonly reason: 'merge' | 'revert' | 'fixup' | 'fixup-amend' | 'squash' }
  | { readonly kind: 'conventional'; readonly commit: ConventionalCommit }
  | { readonly kind: 'malformed' };

export interface LintDiagnostic {
  readonly line: number;
  readonly rule: string;
  readonly message: string;
}
