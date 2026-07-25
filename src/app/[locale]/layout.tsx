import { themeInitScript } from '@atomicloud/diene.frontend-utils/theme';
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { routing } from '@/i18n/routing';
import { clientSafeConfig, serverConfig, serverLandscape } from '@/lib/server-config';
import { Providers } from '@/adapters/atomi/Providers';
import '@/styles/globals.css';

export function generateStaticParams() {
  return routing.locales.map(locale => ({ locale }));
}

export async function generateMetadata(): Promise<Metadata> {
  const config = await serverConfig();
  const branding = config.get('branding');
  const seo = config.get('seo');
  return {
    title: { template: seo.titleTemplate, default: seo.defaultTitle },
    description: seo.defaultDescription,
    metadataBase: new URL(seo.baseUrl),
    manifest: '/api/manifest',
    icons: { icon: branding.favicon },
    openGraph: {
      title: seo.defaultTitle,
      description: seo.defaultDescription,
      images: [seo.ogImage],
      siteName: branding.appName,
    },
    twitter: {
      card: seo.twitterCard,
      site: seo.twitterSite,
    },
  };
}

/**
 * The locale layout is where the server tells the client: landscape is read
 * from the runtime binding, the config tree is loaded/validated server-side,
 * and only the CLIENT-SAFE subset crosses into the provider stack as the
 * SSR-injected payload.
 */
export default async function LocaleLayout({
  children,
  params,
}: {
  readonly children: ReactNode;
  readonly params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);

  const landscape = serverLandscape();
  const config = await serverConfig();
  const clientConfig = clientSafeConfig(config, landscape);
  const theme = config.get('theme');
  const branding = config.get('branding');

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        <meta name="theme-color" content={branding.themeColor} />
        {/* No-flash theme resolution before first paint (runtime CSS-var mechanism). */}
        <script
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{
            __html: themeInitScript({ storageKey: theme.storageKey, themes: theme.themes }),
          }}
        />
      </head>
      <body className="min-h-dvh bg-background text-foreground antialiased">
        <NextIntlClientProvider>
          <Providers config={clientConfig}>{children}</Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
