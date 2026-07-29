import { describe, it } from 'bun:test';
import should from 'should';
import {
  type DeliveryJob,
  InternalDeliverySigner,
  serializeCanonicalDeliveryEnvelope,
  type WebhookEnvelope,
} from '../../../src/domain/index.ts';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const event: WebhookEnvelope = {
  id: 'event-1',
  tenantId: 'external/acme',
  routeId: 'stripe-paid',
  provider: 'stripe',
  landingLandscape: 'raichu',
  receivedAtMs: 0,
  providerTimestampMs: 1_000,
  providerSequence: 'sequence-9',
  providerEventId: 'evt_native',
  dedupId: 'native:ZXZ0X25hdGl2ZQ',
  rawBody: Uint8Array.from([0, 1, 255]),
  headers: {
    'x-request-id': 'request-1',
    'content-type': 'application/json',
  },
  verificationMetadata: { verifier: 'stripe' },
  obligations: [],
};

const job: DeliveryJob = {
  id: 'event-1:receiver',
  eventId: event.id,
  tenantId: event.tenantId,
  routeId: event.routeId,
  endpointId: 'receiver',
  address: 'https://receiver.example/webhook',
  addressKind: 'external',
  signingSecretRef: 'delivery/acme',
  createdAtMs: 0,
  dueAtMs: 0,
  retryWindowMs: 60_000,
  status: 'pending',
  attempts: [],
  misrouteRefreshes: 0,
  replayCount: 0,
};

describe('canonical delivery security envelope', () => {
  it('should serialize the documented v1 envelope byte-for-byte', () => {
    // Act
    const body = serializeCanonicalDeliveryEnvelope({ attempt: 1, event, job, replay: false });

    // Assert
    should(decoder.decode(body)).equal(
      '{"version":1,"eventId":"event-1","dedupId":"native:ZXZ0X25hdGl2ZQ","tenantId":"external/acme","routeId":"stripe-paid","provider":"stripe","landingLandscape":"raichu","receivedAt":"1970-01-01T00:00:00.000Z","providerEventId":"evt_native","providerTimestamp":"1970-01-01T00:00:01.000Z","providerSequence":"sequence-9","providerHeaders":{"content-type":["application/json"],"x-request-id":["request-1"]},"payload":{"contentType":"application/json","bodyBase64":"AAH/"},"delivery":{"endpointId":"receiver","attempt":1,"replay":false}}',
    );
  });

  it('should bind tenant, route, endpoint, event, dedup, attempt, replay, and payload identity into the MAC', () => {
    // Arrange
    const signer = new InternalDeliverySigner();
    const secret = encoder.encode('consumer-secret');
    const body = serializeCanonicalDeliveryEnvelope({ attempt: 1, event, job, replay: false });
    const signed = signer.sign(body, secret, 10);
    const parsed = JSON.parse(decoder.decode(body)) as Record<string, unknown>;
    const delivery = parsed.delivery as Record<string, unknown>;
    const payload = parsed.payload as Record<string, unknown>;
    const mutations = [
      { ...parsed, tenantId: 'external/attacker' },
      { ...parsed, routeId: 'other-route' },
      { ...parsed, eventId: 'other-event' },
      { ...parsed, dedupId: 'native:YXR0YWNrZXI' },
      { ...parsed, provider: 'discord' },
      { ...parsed, landingLandscape: 'celebi' },
      { ...parsed, receivedAt: '1970-01-01T00:00:02.000Z' },
      { ...parsed, providerTimestamp: '1970-01-01T00:00:03.000Z' },
      { ...parsed, providerSequence: 'sequence-10' },
      { ...parsed, delivery: { ...delivery, endpointId: 'other-endpoint' } },
      { ...parsed, delivery: { ...delivery, attempt: 2 } },
      { ...parsed, delivery: { ...delivery, replay: true } },
      { ...parsed, payload: { ...payload, contentType: 'application/octet-stream' } },
      { ...parsed, payload: { ...payload, bodyBase64: 'Zm9yZ2Vk' } },
    ];

    // Act
    const originalValid = signer.verify(signed.header, body, secret, 10);
    const mutationValidity = mutations.map(mutation =>
      signer.verify(signed.header, encoder.encode(JSON.stringify(mutation)), secret, 10),
    );

    // Assert
    should(originalValid).be.true();
    should(mutationValidity).have.length(14);
    should(mutationValidity.every(valid => !valid)).be.true();
  });

  it('should produce distinct replay bytes and a fresh valid signature', () => {
    // Arrange
    const signer = new InternalDeliverySigner();
    const secret = encoder.encode('consumer-secret');
    const initialBody = serializeCanonicalDeliveryEnvelope({ attempt: 1, event, job, replay: false });
    const replayBody = serializeCanonicalDeliveryEnvelope({ attempt: 2, event, job, replay: true });

    // Act
    const initial = signer.sign(initialBody, secret, 10);
    const replay = signer.sign(replayBody, secret, 11);

    // Assert
    should(decoder.decode(initialBody)).not.equal(decoder.decode(replayBody));
    should(initial.header).not.equal(replay.header);
    should(signer.verify(initial.header, initialBody, secret, 10)).be.true();
    should(signer.verify(replay.header, replayBody, secret, 11)).be.true();
    should(signer.verify(initial.header, replayBody, secret, 10)).be.false();
  });
});
