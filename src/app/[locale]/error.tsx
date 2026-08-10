'use client';

import { toProblem } from '@atomicloud/diene.frontend-utils/content';
import { useTranslations } from 'next-intl';
import { useEffect } from 'react';
import { getFaro } from '@/adapters/atomi/faro';
import { defaultProblemView } from '@/components/problem/DefaultProblemView';

/**
 * Route error boundary: any unexpected exception wraps into a LocalError
 * Problem (message + stacktrace in `data`), renders through the Problem
 * visualizer, and STILL propagates to faro — never a raw exception on screen.
 */
export default function LocaleError({
  error,
  reset,
}: {
  readonly error: Error & { digest?: string };
  readonly reset: () => void;
}) {
  const t = useTranslations('error');
  const problem = toProblem(error);

  useEffect(() => {
    getFaro()?.api.pushError(error);
  }, [error]);

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-xl flex-col justify-center gap-4 px-4 py-12">
      <h1 className="text-2xl font-semibold">{t('title')}</h1>
      {defaultProblemView(problem)}
      <button
        type="button"
        onClick={reset}
        className="h-12 rounded-lg bg-primary px-6 font-medium text-primary-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {t('recoverableHint')}
      </button>
    </main>
  );
}
