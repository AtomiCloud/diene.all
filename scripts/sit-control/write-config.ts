import { resolve } from 'node:path';

const target = process.argv[2];
if (target === undefined || !target.startsWith('/')) {
  throw new Error('write-config requires an absolute material directory');
}
const publicOrigin = process.env.MERCURY_SIT_PUBLIC_ORIGIN?.trim() || 'https://127.0.0.1:8443';

const config = (landscape: 'lapras' | 'farfetch', redisHost: string): string => {
  const localLandscapes = landscape === 'lapras' ? '\n        - lapras' : ' []';
  const localAddresses = landscape === 'lapras' ? '\n        lapras: http://sink-coordinate:8080' : ' {}';
  return `app:
  landscape: ${landscape}
  platform: mercury
  service: webhook
  module: hooks
  version: sit
  bind: 0.0.0.0
  port: 8080
  publicOrigin: ${publicOrigin}
  previewDeliveryVisible: false
  shutdownGraceMs: 15000
storage:
  redisUrl: redis://${redisHost}:6379
  postgresUrl: postgres://mercury:mercury@neon:5432/mercury
  archiveEndpoint: http://tigris:9000
  archiveBucket: mercury-webhook-archive
  archiveRegion: us-east-1
security:
  consoleSessionSecretFile: /var/run/secrets/mercury/console-session-secret
  managementBootstrapTokenFile: /var/run/secrets/mercury/management-bootstrap-token
  providerSecretRoot: /var/run/secrets/mercury/providers
  endpointSecretRoot: /var/run/secrets/mercury/endpoints
  archiveAccessKeyIdFile: /var/run/secrets/mercury/archive-access-key-id
  archiveSecretAccessKeyFile: /var/run/secrets/mercury/archive-secret-access-key
  consoleAuthorizationPrivateKeyFile: /var/run/secrets/mercury/console-authorization-private-key
  consoleAuthorizationPublicKeyFile: /var/run/secrets/mercury/console-authorization-public-key
  managementIssuer: mercury-sit
  managementAudience: mercury-management
topology:
  services:
    sit-sink/webhook:
      module: webhook
      localLandscapes:${localLandscapes}
      localAddressByLandscape:${localAddresses}
      canonicalVlandscape: lapras
      canonicalAddress: http://sink-canonical:8080
providerOperations:
  apple:
    enabled: false
    operationKey: apple-notification-history
    preferredHostLandscape: lapras
    intakePath: /t/sit/apple-app-store
    leaseDurationMs: 60000
    pageSize: 100
    intervalMs: 3600000
    jwt:
      issuerId: 00000000-0000-4000-8000-000000000001
      keyId: SITKEY0001
      bundleId: cloud.atomi.mercury.sit
      signingKeySecretRef: apple-app-store-history.p8
    history:
      environment: Sandbox
      request:
        startDateMs: 0
        endDateMs: 1
  google:
    enabled: false
    subscriptionName: projects/mercury-sit/subscriptions/google-play
    deadLetterTopic: projects/mercury-sit/topics/google-play-dlq
    deadLetterMaxDeliveryAttempts: 5
    registeredPushUrl: ${publicOrigin}/t/sit/google-play
    oidcServiceAccountEmail: mercury-sit@mercury-sit.iam.gserviceaccount.com
    oidcAudience: ${publicOrigin}/t/sit/google-play
    intervalMs: 3600000
    oauth:
      credentialSecretRef: google-pubsub-service-account.json
      expectedServiceAccountEmail: mercury-sit@mercury-sit.iam.gserviceaccount.com
      scopes:
        - https://www.googleapis.com/auth/pubsub
otel:
  logs:
    enabled: true
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: "", headers: {}, protocol: http/protobuf, timeout: PT10S}
  metrics:
    enabled: true
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: "", headers: {}, protocol: http/protobuf, timeout: PT10S}
    interval: PT60S
  traces:
    enabled: true
    exporter:
      console: {enabled: false}
      otlp: {enabled: false, endpoint: "", headers: {}, protocol: http/protobuf, timeout: PT10S}
    sampler: {ratio: 1, type: parentbased_traceidratio}
`;
};

await Promise.all([
  Bun.write(resolve(target, 'mercury-lapras.yaml'), config('lapras', 'upstash-lapras')),
  Bun.write(resolve(target, 'mercury-farfetch.yaml'), config('farfetch', 'upstash-farfetch')),
]);
