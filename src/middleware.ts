import createMiddleware from 'next-intl/middleware';
import { routing } from '@/i18n/routing';

// Middleware stays edge-style only (App-Router-on-Workers caveat 3): locale
// negotiation is the single concern here — auth guards live in server
// components/route handlers on the Node runtime.
export default createMiddleware(routing);

export const config = {
  matcher: ['/((?!api|_next|_vercel|\\.well-known|.*\\..*).*)'],
};
