'use client';

import { useLocale, useTranslations } from 'next-intl';
import { routing, type AppLocale } from '@/i18n/routing';
import { usePathname, useRouter } from '@/i18n/navigation';

/** Locale switcher: switching re-renders every translated key via routing. */
export function LocaleSwitcher() {
  const t = useTranslations('locale');
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();

  return (
    <label className="flex h-11 items-center gap-2 rounded-lg border border-border bg-card px-3">
      <span className="sr-only">{t('switch')}</span>
      <select
        aria-label={t('switch')}
        value={locale}
        onChange={event => router.replace(pathname, { locale: event.target.value as AppLocale })}
        className="bg-transparent text-sm outline-none"
      >
        {routing.locales.map(candidate => (
          <option key={candidate} value={candidate}>
            {t(candidate)}
          </option>
        ))}
      </select>
    </label>
  );
}
