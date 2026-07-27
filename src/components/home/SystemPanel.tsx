'use client';

import type { ContentState } from '@atomicloud/diene.frontend-utils/content';
import { renderContentState } from '@atomicloud/diene.frontend-utils/content/react';
import { useTranslations } from 'next-intl';
import { useEffect, useMemo, useState } from 'react';
import { useClientConfig, useLandscape } from '@/adapters/atomi/ClientConfigProvider';
import { useModules } from '@/adapters/atomi/Providers';
import { ErrorTier } from '@/components/ui/ErrorTier';
import { Skeleton } from '@/components/ui/Skeleton';
import { runContentFlow } from '@/lib/content-flow';

interface SystemInfo {
  readonly landscape: string;
  readonly service: string;
}

/**
 * The home page's live system panel: resolves the content-store factory and
 * Problem-view registry through the module registry (DI resolution journey),
 * drives the L/E/E state machine through the template's own content flow
 * (`src/lib/content-flow`, which owns the emptiness policy), and renders the
 * SSR-fed landscape — exercising the module, landscape, and content dogfood
 * surfaces in one place.
 */
export function SystemPanel() {
  const t = useTranslations('content');
  const config = useClientConfig();
  const landscape = useLandscape();
  const modules = useModules();

  const store = useMemo(() => modules?.createContentStore<SystemInfo>(), [modules]);
  const [state, setState] = useState<ContentState<SystemInfo>>({ status: 'loading' });

  const load = useMemo(
    () => async (): Promise<void> => {
      if (store === undefined) return;
      setState({ status: 'loading' });
      const terminal = await runContentFlow(
        store,
        () => ({ landscape, service: config.app.servicetree.service }),
        t('empty'),
      );
      setState(terminal);
    },
    [store, landscape, config.app.servicetree.service, t],
  );

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <section aria-label="system" className="rounded-lg border border-border bg-card p-4">
      {renderContentState(state, {
        loading: () => <Skeleton className="h-6 w-48" />,
        empty: reason => <p className="text-sm text-muted-foreground">{reason || t('empty')}</p>,
        error: problem => <ErrorTier problem={problem} catalog={[]} onRetry={load} />,
        content: info => (
          <p className="text-sm text-muted-foreground">
            <span className="font-medium text-foreground">{info.service}</span> · {info.landscape}
          </p>
        ),
      })}
    </section>
  );
}
