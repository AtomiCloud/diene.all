import type { MetadataRoute } from 'next';
import { serverConfig } from '@/adapters/server-config';

export default async function robots(): Promise<MetadataRoute.Robots> {
  const config = await serverConfig();
  const base = config.get('seo').baseUrl;
  return {
    rules: { userAgent: '*', allow: '/' },
    sitemap: `${base}/sitemap.xml`,
  };
}
