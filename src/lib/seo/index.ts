import type { SeoConfig } from '@/config';

/**
 * SEO module (ported from argon, config-driven per R21): JSON-LD and share
 * surfaces derive purely from the seo config block — nothing is hardcoded, so
 * the rebrand static guard can prove config-drivenness.
 */

export interface JsonLdOrganization {
  readonly '@context': 'https://schema.org';
  readonly '@type': 'Organization';
  readonly name: string;
  readonly url: string;
  readonly logo: string;
}

export const organizationJsonLd = (seo: SeoConfig): JsonLdOrganization => ({
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: seo.jsonLdOrganization.name,
  url: seo.jsonLdOrganization.url,
  logo: seo.jsonLdOrganization.logo,
});

/** Absolute URL for a path under the configured base (share cards need absolutes). */
export const absoluteUrl = (seo: SeoConfig, path: string): string => new URL(path, seo.baseUrl).toString();
