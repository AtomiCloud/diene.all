import type { DeeplinkConfig } from '@/config';

/**
 * Well-known deeplink documents (AASA + assetlinks), built purely from config
 * (R21: app ids and fingerprints are never hardcoded). Pure builders — the
 * route handlers serve them; the well-known schema gate validates the output.
 */

export interface AppleAppSiteAssociation {
  readonly applinks: {
    readonly details: readonly {
      readonly appIDs: readonly string[];
      readonly components: readonly { readonly '/': string }[];
    }[];
  };
}

export interface AssetLink {
  readonly relation: readonly string[];
  readonly target: {
    readonly namespace: 'android_app';
    readonly package_name: string;
    readonly sha256_cert_fingerprints: readonly string[];
  };
}

export const buildAasa = (deeplink: DeeplinkConfig, webPatterns: readonly string[]): AppleAppSiteAssociation => ({
  applinks: {
    details: [
      {
        appIDs: [deeplink.appleAppId],
        components: webPatterns.map(pattern => ({ '/': pattern.replace(/:[A-Za-z][A-Za-z0-9]*/g, '*') })),
      },
    ],
  },
});

export const buildAssetLinks = (deeplink: DeeplinkConfig): readonly AssetLink[] => [
  {
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: deeplink.androidPackage,
      sha256_cert_fingerprints: deeplink.androidSha256Fingerprints,
    },
  },
];
