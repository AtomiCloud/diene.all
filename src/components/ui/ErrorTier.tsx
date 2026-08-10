'use client';

import type { Problem } from '@atomicloud/diene.problems';
import { useTranslations } from 'next-intl';
import { useState } from 'react';
import { classifyProblem, type Classification } from '@/lib/error-classification';
import type { ProblemCatalogEntry } from '@atomicloud/diene.problems';
import { getFaro } from '@/adapters/atomi/faro';
import { AsyncButton } from './AsyncButton';
import { defaultProblemView } from '@/components/problem/DefaultProblemView';

/**
 * Error-tier component wired to the Problem catalog's `recoverable` flag:
 * tier 1 renders inline retry, tier 2 stays on the page with the Problem view,
 * tier 3 (uncatalogued) is full-failure + copy-error and reports to the
 * catalog loop via faro.
 */
export function ErrorTier({
  problem,
  catalog,
  onRetry,
}: {
  readonly problem: Problem;
  readonly catalog: readonly ProblemCatalogEntry[];
  readonly onRetry: () => Promise<void>;
}) {
  const t = useTranslations('error');
  const [copied, setCopied] = useState(false);
  const classification: Classification = classifyProblem(problem, catalog);

  if (classification.tier === 'recoverable') {
    return (
      <div role="alert" className="flex items-center gap-3 rounded-lg border border-border bg-card p-4">
        <p className="flex-1 text-sm">{problem.title}</p>
        <AsyncButton variant="secondary" onAction={onRetry}>
          {t('recoverableHint')}
        </AsyncButton>
      </div>
    );
  }

  if (classification.tier === 'uncatalogued') {
    getFaro()?.api.pushError(new Error(`uncatalogued problem: ${problem.type}`));
  }

  return (
    <div className="flex flex-col gap-3">
      {defaultProblemView(problem)}
      {classification.tier === 'uncatalogued' ? (
        <AsyncButton
          variant="secondary"
          onAction={async () => {
            await navigator.clipboard.writeText(JSON.stringify(problem, null, 2));
            setCopied(true);
          }}
        >
          {copied ? t('copied') : t('copy')}
        </AsyncButton>
      ) : null}
    </div>
  );
}
