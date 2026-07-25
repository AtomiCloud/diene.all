'use client';

import { Content, ProblemView } from '@atomicloud/diene.frontend-utils/content/react';
import { useTranslations } from 'next-intl';
import { useEffect, useMemo } from 'react';
import { useClientConfig, useLandscape } from '@/adapters/atomi/ClientConfigProvider';
import { useModules } from '@/adapters/atomi/Providers';
import { Skeleton } from '@/components/ui/Skeleton';

interface SystemInfo {
  readonly landscape: string;
  readonly service: string;
}

/**
 * The home page's live system panel: resolves the content-store factory and
 * Problem-view registry through the module registry (DI resolution journey),
 * loads through the L/E/E state machine, and renders the SSR-fed landscape —
 * exercising the module, landscape, and content dogfood surfaces in one place.
 */
export function SystemPanel() {
  const t = useTranslations('content');
  const config = useClientConfig();
  const landscape = useLandscape();
  const { createContentStore, problemViews } = useModules();

  const store = useMemo(() => createContentStore<SystemInfo>(), [createContentStore]);

  useEffect(() => {
    void store.load(() => ({
      landscape,
      service: config.app.servicetree.service,
    }));
  }, [store, landscape, config.app.servicetree.service]);

  return (
    <section aria-label="system" className="rounded-lg border border-border bg-card p-4">
      <Content
        store={store}
        loading={() => <Skeleton className="h-6 w-48" />}
        empty={reason => <p className="text-sm text-muted-foreground">{reason || t('empty')}</p>}
        error={problem => <ProblemView registry={problemViews} problem={problem} />}
        content={info => (
          <p className="text-sm text-muted-foreground">
            <span className="font-medium text-foreground">{info.service}</span> · {info.landscape}
          </p>
        )}
      />
    </section>
  );
}
