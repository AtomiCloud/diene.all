import { isLocalError } from '@atomicloud/diene.frontend-utils/content';
import type { Problem } from '@atomicloud/diene.problems';
import type { ProblemView } from '@atomicloud/diene.frontend-utils/content/react';
import type { ReactNode } from 'react';

/**
 * The mandatory fallback Problem view: any Problem — including LocalError and
 * uncatalogued types — renders a sane, copyable view instead of a blank screen
 * or a raw exception (Problem boundary gate).
 */
export const defaultProblemView: ProblemView<ReactNode> = (problem: Problem) => (
  <div role="alert" className="problem-view rounded-lg border border-destructive/40 bg-card p-6">
    <p className="text-sm font-medium uppercase tracking-wide text-muted-foreground">
      {problem.status} · {problem.type}
    </p>
    <h2 className="mt-1 text-lg font-semibold text-foreground">{problem.title}</h2>
    {problem.detail !== undefined && problem.detail !== '' ? (
      <p className="mt-2 text-sm text-muted-foreground">{problem.detail}</p>
    ) : null}
    {isLocalError(problem) ? (
      <details className="mt-3 text-xs text-muted-foreground">
        <summary>Technical details</summary>
        <pre className="mt-2 max-h-48 overflow-auto whitespace-pre-wrap">
          {problem.data.message}
          {problem.data.stack === undefined ? '' : `\n\n${problem.data.stack}`}
        </pre>
      </details>
    ) : null}
  </div>
);
