'use client';

import { toProblem } from '@atomicloud/diene.frontend-utils/content';
import { useEffect } from 'react';
import { getFaro } from '@/adapters/atomi/faro';
import { defaultProblemView } from '@/components/problem/DefaultProblemView';

/**
 * Root error boundary (replaces argon's GlobalErrorBoundary): the last-resort
 * Problem view when even the locale layout failed. Renders its own <html>
 * because the root layout is gone at this point.
 */
export default function GlobalError({ error }: { readonly error: Error & { digest?: string } }) {
  const problem = toProblem(error);

  useEffect(() => {
    getFaro()?.api.pushError(error);
  }, [error]);

  return (
    <html lang="en">
      <body>
        <main style={{ maxWidth: '36rem', margin: '4rem auto', padding: '0 1rem' }}>{defaultProblemView(problem)}</main>
      </body>
    </html>
  );
}
