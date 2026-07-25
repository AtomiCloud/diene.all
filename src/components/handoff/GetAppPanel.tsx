'use client';

import { useTranslations } from 'next-intl';
import { useState } from 'react';
import { AsyncButton } from '@/components/ui/AsyncButton';

/**
 * Deferred-login hand-off panel ("continue in the app"): asks the server to
 * initiate the handoff against dotnet-api's /app-handoff mount (the server
 * holds the session; auth-engine never enters the browser bundle), then copies
 * the iOS clipboard carrier. dotnet-api enforces the 15-minute nonce TTL and
 * the 120 s one-time redeem token.
 */
export function GetAppPanel() {
  const t = useTranslations('onboarding');
  const [carrier, setCarrier] = useState<string | undefined>(undefined);
  const [unavailable, setUnavailable] = useState(false);

  if (unavailable) return null;

  return (
    <section
      aria-label="get-the-app"
      className="flex w-full flex-col gap-3 rounded-lg border border-border bg-card p-4"
    >
      <AsyncButton
        variant="secondary"
        onAction={async () => {
          const response = await fetch('/api/handoff/initiate', { method: 'POST' });
          if (!response.ok) {
            setUnavailable(true);
            return;
          }
          const body = (await response.json()) as { iosClipboardPayload: string };
          setCarrier(body.iosClipboardPayload);
          await navigator.clipboard.writeText(body.iosClipboardPayload);
        }}
      >
        {t('continue')}
      </AsyncButton>
      {carrier === undefined ? null : (
        <p className="break-all rounded-md bg-muted p-3 font-mono text-xs" aria-live="polite">
          {carrier}
        </p>
      )}
    </section>
  );
}
