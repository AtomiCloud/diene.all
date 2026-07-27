import { serverConfig } from '@/adapters/server-config';
import { buildAssetLinks } from '@/lib/deeplink/well-known';

export async function GET(): Promise<Response> {
  const config = await serverConfig();
  return Response.json(buildAssetLinks(config.get('deeplink')));
}
