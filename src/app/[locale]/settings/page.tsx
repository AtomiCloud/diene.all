import { setRequestLocale, getTranslations } from 'next-intl/server';
import { requireSession } from '@/adapters/auth/guard';
import { SettingsForm } from '@/components/settings/SettingsForm';

/** Settings — protected pure renderer; the guard carries returnTo with query. */
export default async function SettingsPage({ params }: { readonly params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  await requireSession('/settings');
  const t = await getTranslations('nav');

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-xl flex-col gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">{t('settings')}</h1>
      <SettingsForm />
    </main>
  );
}
