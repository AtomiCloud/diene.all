import { defineRouting } from 'next-intl/routing';

/**
 * Locale routing: the sample ships English plus one deliberately long-string
 * locale (German) so resize-fluid-under-i18n is exercised by real data.
 */
export const routing = defineRouting({
  locales: ['en', 'de'],
  defaultLocale: 'en',
  // Deterministic prefixes on both server rails: `as-needed` produced a
  // rewrite/redirect loop on the standalone server, and an always-prefixed
  // URL space keeps the deeplink route map one-to-one.
  localePrefix: 'always',
});

export type AppLocale = (typeof routing.locales)[number];
