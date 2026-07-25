import { serverConfig } from '@/lib/server-config';

// PWA manifest served from config (R21): branding values are never hardcoded.
export async function GET(): Promise<Response> {
  const config = await serverConfig();
  const branding = config.get('branding');
  const manifest = {
    name: branding.appName,
    short_name: branding.shortName,
    description: branding.description,
    start_url: '/',
    display: 'standalone',
    theme_color: branding.themeColor,
    background_color: branding.backgroundColor,
    icons: [
      { src: branding.logo, sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: branding.logo, sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
  };
  return Response.json(manifest, {
    headers: { 'content-type': 'application/manifest+json' },
  });
}
