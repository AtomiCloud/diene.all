import { setRequestLocale, getTranslations } from 'next-intl/server';
import { redirect } from '@/i18n/navigation';
import { requireSession } from '@/adapters/auth/guard';
import { OnboardingClient } from '@/components/onboarding/OnboardingClient';

/**
 * Onboarding page — pure renderer over the guard's decision: an existing-home
 * user never sees the picker (picker-journey gate); a fresh user goes through
 * legal → Doc B picker → confirm → OnboardSync (driven client-side through
 * auth-engine).
 */
export default async function OnboardingPage({ params }: { readonly params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations('onboarding');

  const session = await requireSession('/onboarding');
  if (session.home.phase === 'home') {
    redirect({ href: '/', locale });
  }

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-xl flex-col justify-center gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">{t('title')}</h1>
      <OnboardingClient />
    </main>
  );
}
