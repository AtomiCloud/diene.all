import { defineRouting } from 'next-intl/routing';

/**
 * Locale routing: the sample ships English plus one deliberately long-string
 * locale (German) so resize-fluid-under-i18n is exercised by real data.
 */
export const routing = defineRouting({
  locales: ['en', 'de'],
  defaultLocale: 'en',
  localePrefix: 'as-needed',
});

export type AppLocale = (typeof routing.locales)[number];
