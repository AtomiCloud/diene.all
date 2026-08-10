'use client';

import { useTranslations } from 'next-intl';
import { useRouter } from '@/i18n/navigation';
import { PickerFlow } from '@/components/picker/PickerFlow';

/**
 * Client half of onboarding: runs the picker flow, then posts the confirmed
 * home assignment to the onboarding sync endpoint (auth-engine's OnboardSync
 * writes the home claim server-side) and lands on /finish.
 */
export function OnboardingClient() {
  const t = useTranslations('onboarding');
  const router = useRouter();

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">{t('pending')}</p>
      <PickerFlow
        onConfirmed={async landscape => {
          const response = await fetch('/api/onboarding/sync', {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ landscape }),
          });
          if (response.ok) router.push('/finish');
        }}
      />
    </div>
  );
}
