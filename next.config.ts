import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';
import FaroSourceMapUploaderPlugin from '@grafana/faro-webpack-plugin';
import { buildTimeValueMap } from '@atomicloud/diene.config/build-time';

// Build-time config tier: ATOMI_-prefixed env scanned at build, frozen into the
// artifact via DefinePlugin (client/build-time dimension). The faro source-map
// upload key (`ATOMI_CLIENT__FARO__BUILD__KEY`) is a BUILD-TIME SECRET: CI
// injects it right before the OpenNext build; it feeds the webpack plugin below
// and is never persisted into the bundle.
const buildTimeEnv = buildTimeValueMap(process.env, 'ATOMI_');
const landscape = process.env['ATOMI_LANDSCAPE'] ?? process.env['LANDSCAPE'] ?? 'base';

const faroBuild = {
  enabled: process.env['ATOMI_CLIENT__FARO__BUILD__ENABLED'] === 'true',
  endpoint: process.env['ATOMI_CLIENT__FARO__BUILD__ENDPOINT'] ?? '',
  app: process.env['ATOMI_CLIENT__FARO__BUILD__APP'] ?? '',
  stack: process.env['ATOMI_CLIENT__FARO__BUILD__STACK'] ?? '',
  key: process.env['ATOMI_CLIENT__FARO__BUILD__KEY'] ?? '',
};

const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

const nextConfig: NextConfig = {
  // The Garden rail boots `.next/standalone/server.js`; OpenNext consumes the
  // same build for the Workers rail.
  output: 'standalone',
  // Browser source maps feed the faro upload plugin (Layer B/C); serving them
  // is harmless (they never embed secrets — config secrets are runtime-only).
  productionBrowserSourceMaps: true,
  // `next/image` rides the Cloudflare Images binding on Workers (caveat 5);
  // the default optimizer route does not exist there.
  images: { unoptimized: true },
  serverExternalPackages: ['jose'],
  webpack: (config, { webpack, isServer, dev }) => {
    config.module.rules.push({ test: /\.ya?ml$/, use: 'yaml-loader' });

    if (!dev) {
      // TEMPORARY (see src/shims/jsx-dev-runtime.ts): frontend-utils@1.0.0
      // dist references react/jsx-dev-runtime, whose jsxDEV export is
      // undefined in production React. Redirect those requests to the
      // delegating shim (production builds only; dev keeps the real dev
      // runtime) until the 1.0.1 rebuild lands upstream. A plugin is used
      // because Next.js owns resolve.alias for react/* and wins over it.
      const shim = new URL('./src/shims/jsx-dev-runtime.ts', import.meta.url).pathname;
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(
          /^react\/jsx-dev-runtime(\.js)?$/,
          (resource: { request: string }) => {
            resource.request = shim;
          },
        ),
      );
    }

    if (!isServer) {
      // The diene libs are universal: their Node-only file helpers sit behind
      // guards, but the `node:` specifiers still reach the client graph.
      // Rewrite the scheme and stub the modules so the client bundle stays
      // browser-pure (tree-shaking drops the guarded code paths).
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(/^node:/, (resource: { request: string }) => {
          resource.request = resource.request.replace(/^node:/, '');
        }),
      );
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        path: false,
        os: false,
        crypto: false,
      };
    }

    config.plugins.push(
      new webpack.DefinePlugin({
        'process.env.BUILD_TIME_VARIABLES': JSON.stringify(JSON.stringify(buildTimeEnv)),
        'process.env.NEXT_PUBLIC_LANDSCAPE_BUILD_DEFAULT': JSON.stringify(landscape),
      }),
    );

    // Faro source-map upload (caveat 9): invoked inline from this webpack hook
    // during the OpenNext build. Layer B (PR CI) dry-runs without creds; Layer
    // C (pre-release) supplies the real key.
    if (faroBuild.enabled && faroBuild.key !== '') {
      config.plugins.push(
        new FaroSourceMapUploaderPlugin({
          appName: faroBuild.app,
          endpoint: faroBuild.endpoint,
          appId: faroBuild.app,
          stackId: faroBuild.stack,
          apiKey: faroBuild.key,
          gzipContents: true,
        }),
      );
    }
    return config;
  },
};

export default withNextIntl(nextConfig);
