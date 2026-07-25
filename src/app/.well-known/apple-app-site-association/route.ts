import { serverConfig } from '@/adapters/server-config';
import { buildAasa } from '@/lib/deeplink/well-known';
import { DEEPLINK_ROUTES } from '@/lib/deeplink/route-map';

// AASA must be served as JSON at /.well-known/apple-app-site-association
// with no redirect and no extension.
export async function GET(): Promise<Response> {
  const config = await serverConfig();
  const aasa = buildAasa(
    config.get('deeplink'),
    DEEPLINK_ROUTES.map(route => route.web),
  );
  return Response.json(aasa, { headers: { 'content-type': 'application/json' } });
}
