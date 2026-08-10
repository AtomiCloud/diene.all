import { setRequestLocale, getTranslations } from 'next-intl/server';
import { requireSession } from '@/adapters/auth/guard';

/** Profile — protected pure renderer over the guard's claims. */
export default async function ProfilePage({ params }: { readonly params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await requireSession('/profile');
  const t = await getTranslations('nav');

  const subject = typeof session.claims['sub'] === 'string' ? session.claims['sub'] : '—';
  const home = session.home.phase === 'home' ? session.home.landscape : '—';

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-xl flex-col gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">{t('profile')}</h1>
      <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 rounded-lg border border-border bg-card p-6 text-sm">
        <dt className="font-medium">Subject</dt>
        <dd className="text-muted-foreground">{subject}</dd>
        <dt className="font-medium">Home landscape</dt>
        <dd className="text-muted-foreground">{home}</dd>
      </dl>
    </main>
  );
}
