import type { MetadataRoute } from 'next';
import { serverConfig } from '@/lib/server-config';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const config = await serverConfig();
  const base = config.get('seo').baseUrl;
  return [
    { url: base, changeFrequency: 'weekly', priority: 1 },
    { url: `${base}/de`, changeFrequency: 'weekly', priority: 0.8 },
  ];
}
