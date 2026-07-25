import { setRequestLocale } from 'next-intl/server';
import { useTranslations } from 'next-intl';
import { use } from 'react';
import { SearchBar } from '@/components/home/SearchBar';
import { SystemPanel } from '@/components/home/SystemPanel';
import { ThemeToggle } from '@/components/shell/ThemeToggle';
import { LocaleSwitcher } from '@/components/shell/LocaleSwitcher';

/**
 * Home page — a PURE RENDERER: no service imports, no data access; it renders
 * translations and mounts client components (arch-lint enforces this shape).
 */
export default function HomePage({ params }: { readonly params: Promise<{ locale: string }> }) {
  const { locale } = use(params);
  setRequestLocale(locale);
  const t = useTranslations('home');

  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-3xl flex-col gap-8 px-4 py-12">
      <header className="flex items-center justify-between gap-4">
        <h1 className="text-3xl font-bold tracking-tight">{t('title')}</h1>
        <div className="flex items-center gap-2">
          <LocaleSwitcher />
          <ThemeToggle />
        </div>
      </header>
      <p className="text-lg text-muted-foreground">{t('tagline')}</p>
      <SearchBar />
      <SystemPanel />
    </main>
  );
}
