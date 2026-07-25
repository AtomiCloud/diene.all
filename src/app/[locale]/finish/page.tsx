import { setRequestLocale, getTranslations } from 'next-intl/server';
import { Link } from '@/i18n/navigation';
import { GetAppPanel } from '@/components/handoff/GetAppPanel';
import { CelebrationLottie } from '@/components/lottie/CelebrationLottie';

/** Post-onboarding landing — a pure renderer. */
export default async function FinishPage({ params }: { readonly params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const t = await getTranslations('onboarding');

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-xl flex-col items-center justify-center gap-6 px-4 py-12 text-center">
      <CelebrationLottie />
      <h1 className="text-3xl font-bold">{t('finish')}</h1>
      <GetAppPanel />
      <Link
        href="/"
        className="inline-flex h-12 items-center rounded-lg bg-primary px-6 font-medium text-primary-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {t('continue')}
      </Link>
    </main>
  );
}
