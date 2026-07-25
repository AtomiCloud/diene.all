'use client';

import { useTranslations } from 'next-intl';
import { useEffect, useState } from 'react';
import type { DocB } from '@atomicloud/diene.frontend-utils/discovery';
import { useClientConfig } from '@/adapters/atomi/ClientConfigProvider';
import { confirmHome, fetchDocB, pingAll, type PingResult } from '@/adapters/picker/client';
import { AsyncButton } from '@/components/ui/AsyncButton';
import { Skeleton } from '@/components/ui/Skeleton';

/**
 * Pre-onboarding picker (ARCHITECTURE §4/§5, SIGN-UP ONLY): a legal/consent
 * step precedes everything (app-handoff legal gate), then Doc B fetch →
 * ping each landscape → the user confirms home → the assignment hands off to
 * auth-engine, whose OIDC login + OnboardSync writes the home claim.
 */
export function PickerFlow({ onConfirmed }: { readonly onConfirmed: (landscape: string) => Promise<void> }) {
  const t = useTranslations('picker');
  const config = useClientConfig();
  const [consented, setConsented] = useState(false);
  const [doc, setDoc] = useState<DocB | undefined>(undefined);
  const [pings, setPings] = useState<readonly PingResult[] | undefined>(undefined);
  const [chosen, setChosen] = useState<string | undefined>(undefined);

  useEffect(() => {
    if (!consented) return;
    let cancelled = false;
    void (async () => {
      const fetched = await fetchDocB(config.picker);
      if (cancelled) return;
      setDoc(fetched);
      const results = await pingAll(fetched, config.picker);
      if (!cancelled) setPings(results);
    })();
    return () => {
      cancelled = true;
    };
  }, [consented, config.picker]);

  if (!consented) {
    // Legal/consent step MUST precede onboarding (app-handoff legal gate).
    return (
      <section aria-label="legal" className="flex flex-col gap-4 rounded-lg border border-border bg-card p-6">
        <h2 className="text-xl font-semibold">{t('legalTitle')}</h2>
        <p className="text-sm text-muted-foreground">{t('legalBody')}</p>
        <AsyncButton
          onAction={async () => {
            setConsented(true);
          }}
        >
          {t('legalAccept')}
        </AsyncButton>
      </section>
    );
  }

  if (doc === undefined || pings === undefined) {
    return (
      <section aria-label="measuring" className="flex flex-col gap-3 rounded-lg border border-border bg-card p-6">
        <p className="text-sm text-muted-foreground">{t('measuring')}</p>
        <Skeleton className="h-12 w-full" />
        <Skeleton className="h-12 w-full" />
      </section>
    );
  }

  return (
    <section aria-label="picker" className="flex flex-col gap-4 rounded-lg border border-border bg-card p-6">
      <h2 className="text-xl font-semibold">{t('title')}</h2>
      <p className="text-sm text-muted-foreground">{t('explainer')}</p>
      <ul className="flex flex-col gap-2">
        {pings.map(ping => (
          <li key={ping.landscape}>
            <label className="flex h-12 cursor-pointer items-center gap-3 rounded-lg border border-border px-4">
              <input
                type="radio"
                name="home-landscape"
                value={ping.landscape}
                checked={chosen === ping.landscape}
                disabled={!ping.reachable}
                onChange={() => setChosen(ping.landscape)}
              />
              <span className="flex-1 font-medium">
                {doc.landscapes.find(entry => entry.name === ping.landscape)?.displayName ?? ping.landscape}
              </span>
              <span className="text-sm text-muted-foreground">
                {ping.reachable ? `${Math.round(ping.latencyMs)} ms` : '—'}
              </span>
            </label>
          </li>
        ))}
      </ul>
      <AsyncButton
        onAction={async () => {
          if (chosen === undefined) return;
          const handoff = await confirmHome(pings, chosen);
          await onConfirmed(handoff.landscape);
        }}
      >
        {t('confirm')}
      </AsyncButton>
    </section>
  );
}
