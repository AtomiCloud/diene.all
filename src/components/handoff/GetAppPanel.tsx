'use client';

import { ClientAuthStateRetriever, registerAuthProblems } from '@atomicloud/diene.auth-engine';
import { createGenericProblemRegistry } from '@atomicloud/diene.problems';
import { useTranslations } from 'next-intl';
import { useState } from 'react';
import { useClientConfig } from '@/adapters/atomi/ClientConfigProvider';
import { buildIosClipboardPayload, initiateDeferredLogin } from '@/adapters/deferred-login/client';
import { AsyncButton } from '@/components/ui/AsyncButton';

/**
 * Deferred-login hand-off panel ("continue in the app"): initiates the
 * handoff against dotnet-api's /app-handoff mount with the web session's
 * access token, then offers the iOS clipboard carrier (the Android carrier
 * rides the Play install referrer at store link build time). Nonce TTL and
 * the 120 s one-time redeem token are enforced server-side by dotnet-api.
 */
export function GetAppPanel({ dotnetApiBackend }: { readonly dotnetApiBackend: string }) {
  const t = useTranslations('onboarding');
  const config = useClientConfig();
  const [carrier, setCarrier] = useState<string | undefined>(undefined);

  const backend = config.backends[dotnetApiBackend];
  if (backend === undefined) return null;

  return (
    <section aria-label="get-the-app" className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <AsyncButton
        variant="secondary"
        onAction={async () => {
          const base = new URL(config.seo.baseUrl);
          const registry = createGenericProblemRegistry({
            scheme: base.protocol === 'http:' ? 'http' : 'https',
            host: base.host,
            landscape: config.landscape,
            platform: config.app.servicetree.platform,
            service: config.app.servicetree.service,
            module: config.app.servicetree.module,
          });
          const retriever = new ClientAuthStateRetriever();
          await registerAuthProblems(registry)
            .andThen(problems =>
              retriever.getTokenSet().andThen(state => {
                if (state.__kind === 'unauthed') {
                  throw new Error('sign in before handing off to the app');
                }
                const accessToken = Object.values(state.value.data.accessTokens)[0] ?? '';
                return initiateDeferredLogin({
                  dotnetApiBaseUrl: backend.baseUrl,
                  mount: '/app-handoff',
                  accessToken,
                  problems,
                });
              }),
            )
            .run(result => {
              const payload = buildIosClipboardPayload(result.nonce);
              setCarrier(payload);
              void navigator.clipboard.writeText(payload);
            })
            .serial();
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
