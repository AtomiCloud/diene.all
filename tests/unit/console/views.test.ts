import { describe, it } from 'bun:test';
import should from 'should';
import type { ConsoleDashboardSnapshot, ConsoleEventDetail, ConsoleIdentity } from '../../../src/console/model.ts';
import {
  escapeHtml,
  renderConfirmation,
  renderDashboard,
  renderEvent,
  renderLogin,
} from '../../../src/console/views.ts';

const identity: ConsoleIdentity = {
  accountId: 'account-1',
  accountName: 'internal/default',
  accountKind: 'default-internal',
};

const event: ConsoleEventDetail = {
  id: 'evt_42',
  landscape: 'serving',
  tenant: 'internal/primordial',
  provider: 'stripe',
  route: 'billing',
  endpointId: 'endpoint-1',
  endpointName: 'Billing Receiver',
  status: 'dead-lettered',
  receivedAt: new Date('2026-07-29T00:00:00.000Z'),
  providerTimestamp: new Date('2026-07-28T23:59:58.000Z'),
  providerSequence: 'seq-9',
  attemptCount: 12,
  lagSeconds: 4_200,
  allowedHeaders: { 'content-type': 'application/json', 'x-safe': '<retained>' },
  metadata: { deduplication: 'provider-native', source: '<provider>' },
  payload: '{"unsafe":"</script><script>alert(1)</script>"}',
  payloadMediaType: 'application/json',
  deliveryAddress: 'http://receiver.internal/hooks',
  lastResponseStatus: 503,
  lastResponseBody: '<html>temporarily unavailable</html>',
};

const snapshot: ConsoleDashboardSnapshot = {
  generatedAt: new Date('2026-07-29T00:01:00.000Z'),
  filterOptions: {
    landscapes: [{ value: 'serving', label: 'Serving', count: 9 }],
    tenants: [{ value: 'internal/primordial', label: 'Primordial', count: 9 }],
    providers: [{ value: 'stripe', label: 'Stripe', count: 9 }],
    endpoints: [{ value: 'endpoint-1', label: 'Billing Receiver', count: 9 }],
  },
  intake: [
    {
      landscape: 'serving',
      state: 'healthy',
      eventsPerMinute: 18.2,
      verificationFailureRate: 0.012,
      dedupHitRate: 0.031,
      lastAcceptedAt: new Date('2026-07-29T00:00:58.000Z'),
    },
  ],
  deliveries: [
    {
      endpointId: 'endpoint-1',
      endpointName: 'Billing Receiver',
      tenant: 'internal/primordial',
      provider: 'stripe',
      landscape: 'serving',
      state: 'critical',
      circuit: 'open',
      successRate: 0.72,
      retryDepth: 18,
      lagSeconds: 4_200,
      deadLetterCount: 3,
      lastAttemptAt: new Date('2026-07-29T00:00:30.000Z'),
      canReenable: true,
    },
  ],
  events: [event],
  deadLetters: [
    {
      eventId: event.id,
      landscape: event.landscape,
      tenant: event.tenant,
      provider: event.provider,
      endpointId: event.endpointId,
      endpointName: event.endpointName,
      exhaustedAt: new Date('2026-07-29T00:00:20.000Z'),
      finalStatus: 503,
      attempts: 12,
    },
  ],
  routes: [
    {
      routeId: 'route-1',
      route: 'billing',
      tenant: 'internal/primordial',
      provider: 'stripe',
      landscape: 'serving',
      endpointCount: 1,
      state: 'active',
      activeGeneration: 43,
    },
  ],
  generations: [
    {
      landscape: 'serving',
      desiredGeneration: 44,
      activeGeneration: 43,
      state: 'stale',
      compiledAt: new Date('2026-07-28T23:58:00.000Z'),
      detail: 'Recompile queued',
    },
  ],
  archives: [
    {
      landscape: 'serving',
      state: 'blocked',
      pendingStreams: 1,
      pendingBytes: 4_194_304,
      lastArchivedAt: new Date('2026-07-28T22:00:00.000Z'),
      deletionBlocked: true,
      detail: 'Tigris write failed; source deletion interlocked.',
    },
  ],
  quotas: [
    {
      tenant: 'internal/primordial',
      state: 'approaching',
      used: 8_100,
      limit: 10_000,
      window: '1 minute',
      resetsAt: new Date('2026-07-29T00:02:00.000Z'),
    },
  ],
  previewVisibility: {
    state: 'withheld-d11',
    detail: 'Preview callback delivery visibility is withheld pending D11.',
    affectedLandscapes: ['castform'],
  },
  sourceFailures: [
    {
      landscape: 'castform',
      operation: 'snapshot',
      kind: 'unavailable',
      detail: 'The authenticated landscape snapshot request timed out or could not connect.',
    },
  ],
};

describe('console views', () => {
  it('escapes untrusted text in HTML text and attribute contexts', () => {
    // Arrange
    const unsafe = "\"><script>alert('x')</script>&";

    // Act
    const escaped = escapeHtml(unsafe);

    // Assert
    should(escaped).equal('&quot;&gt;&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;&amp;');
  });

  it('renders the complete telemetry surface and D11 as visibility state only', () => {
    // Arrange
    const input = {
      nonce: 'nonce-value',
      identity,
      csrfToken: 'csrf-value',
      snapshot,
      filters: { status: 'all' as const },
      capabilities: ['operations:read', 'events:replay', 'endpoints:replay', 'endpoints:reenable'] as const,
    };

    // Act
    const document = renderDashboard(input);

    // Assert
    should(document).containEql('Landscape');
    should(document).containEql('Tenant');
    should(document).containEql('Provider');
    should(document).containEql('Endpoint');
    should(document).containEql('Intake pulse');
    should(document).containEql('Delivery circuits');
    should(document).containEql('Retry depth');
    should(document).containEql('Dead-letter inspection');
    should(document).containEql('Route registry state');
    should(document).containEql('Config generations');
    should(document).containEql('Archive interlock');
    should(document).containEql('Quota state');
    should(document).containEql('data-preview-visibility="withheld-d11"');
    should(document).containEql('controls remain available');
    should(document).containEql('Default internal account');
    should(document).containEql('Account ID · account-1');
    should(document).containEql('landscape source request(s) failed');
    should(document).containEql('Replay endpoint');
    should(document).containEql('/console/endpoints/serving/endpoint-1/replay');
    should(document).containEql('Re-enable');
    should(document).containEql('@media (prefers-reduced-motion: reduce)');
    should(document).containEql('href="#main"');
    should(document).containEql('<caption>');
  });

  it('renders native account login fields without an email identity or credential value', () => {
    // Arrange / Act
    const document = renderLogin({
      nonce: 'nonce-value',
      csrfToken: 'csrf-value',
      accountName: 'internal/default',
    });

    // Assert
    should(document).containEql('name="accountName"');
    should(document).containEql('name="bearerCredential"');
    should(document).containEql('never stored in the console session');
    should(document).not.containEql('Account email');
    should(document).not.containEql('name="password"');
  });

  it('does not render controls outside the scoped native capabilities', () => {
    // Arrange
    const input = {
      nonce: 'nonce-value',
      identity: { ...identity, accountKind: 'external' as const },
      csrfToken: 'csrf-value',
      snapshot,
      filters: { tenant: 'internal/primordial', status: 'all' as const },
      capabilities: ['operations:read'] as const,
    };

    // Act
    const document = renderDashboard(input);

    // Assert
    should(document).containEql('Read only');
    should(document).not.containEql('Replay endpoint</a>');
    should(document).not.containEql('Replay event</a>');
    should(document).not.containEql('>Re-enable</a>');
  });

  it('renders retained metadata and payload as inert escaped content', () => {
    // Arrange
    const maliciousEvent = {
      ...event,
      endpointName: '<img src=x onerror=alert(1)>',
    };

    // Act
    const document = renderEvent({
      nonce: 'nonce-value',
      identity,
      csrfToken: 'csrf-value',
      event: maliciousEvent,
      canReplay: true,
    });

    // Assert
    should(document).containEql('&lt;img src=x onerror=alert(1)&gt;');
    should(document).containEql('&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;');
    should(document).containEql('Provider sequence');
    should(document).containEql('seq-9');
    should(document).not.containEql('<img src=x onerror=alert(1)>');
  });

  it('renders a real, CSRF-bound event replay confirmation form', () => {
    // Arrange
    const input = {
      nonce: 'nonce-value',
      identity,
      csrfToken: 'csrf-value',
      kind: 'replay-event' as const,
      event,
      selectedEndpointId: 'endpoint-1',
    };

    // Act
    const document = renderConfirmation(input);

    // Assert
    should(document).containEql('action="/console/events/serving/evt_42/replay?endpoint=endpoint-1"');
    should(document).containEql('name="csrf" value="csrf-value"');
    should(document).containEql('pattern="REPLAY EVENT"');
    should(document).containEql('name="reason"');
    should(document).containEql('data-confirm-status aria-live="polite"');
  });
});
