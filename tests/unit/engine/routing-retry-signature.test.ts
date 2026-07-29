import { describe, it } from 'bun:test';
import should from 'should';
import {
  boundedRetryWindowMs,
  deriveDedupId,
  InternalDeliverySigner,
  type LandscapeRuntimeConfig,
  NameBlindRouteResolver,
  nextRetry,
} from '../../../src/domain/index.ts';

const encoder = new TextEncoder();

const runtimeConfig: LandscapeRuntimeConfig = {
  generation: 1,
  landscape: 'raichu',
  compiledAtMs: 1,
  sourceRevision: 'one',
  tenants: [
    {
      id: 'external/acme',
      slug: 'acme',
      registeredDomains: ['hooks.acme.example'],
      intakeRps: 10,
      intakeBurst: 20,
      retryWindowMs: 72 * 60 * 60 * 1_000,
      routes: [
        {
          id: 'stripe-paid',
          path: '/stripe/paid',
          canonicalPath: '/t/acme/stripe/paid',
          provider: 'stripe',
          registeredUrl: 'https://hooks.acme.example/stripe/paid',
          verificationSecretRef: 'verify/acme',
          endpoints: [],
        },
      ],
    },
    {
      id: 'external/other',
      slug: 'other',
      registeredDomains: ['hooks.other.example'],
      intakeRps: 10,
      intakeBurst: 20,
      retryWindowMs: 72 * 60 * 60 * 1_000,
      routes: [
        {
          id: 'stripe-paid',
          path: '/stripe/paid',
          canonicalPath: '/t/other/stripe/paid',
          provider: 'stripe',
          registeredUrl: 'https://hooks.other.example/stripe/paid',
          endpoints: [],
        },
      ],
    },
  ],
};

describe('NameBlindRouteResolver', () => {
  it('should resolve canonical paths independently of Host', () => {
    // Arrange
    const subject = new NameBlindRouteResolver();

    // Act
    const actual = subject.resolve(runtimeConfig, '/t/acme/stripe/paid', 'hooks.other.example');

    // Assert
    should(actual).not.be.null();
    should(actual?.tenant.id).equal('external/acme');
  });

  it('should use Host only as an exact registered-domain hint', () => {
    // Arrange
    const subject = new NameBlindRouteResolver();

    // Act
    const exact = subject.resolve(runtimeConfig, '/stripe/paid', 'hooks.acme.example');
    const suffixAttack = subject.resolve(runtimeConfig, '/stripe/paid', 'hooks.acme.example.attacker.test');
    const unknown = subject.resolve(runtimeConfig, '/stripe/paid', 'unregistered.example');

    // Assert
    should(exact?.tenant.id).equal('external/acme');
    should(suffixAttack).be.null();
    should(unknown).be.null();
  });
});

describe('dedup derivation', () => {
  it('should prefer a provider-native id and hash both body and signature otherwise', () => {
    // Arrange
    const body = encoder.encode('{"id":"evt"}');

    // Act
    const native = deriveDedupId('evt_native', body, 'signature-a');
    const fallback = deriveDedupId(undefined, body, 'signature-a');
    const changedSignature = deriveDedupId(undefined, body, 'signature-b');
    const changedBody = deriveDedupId(undefined, encoder.encode('{"id":"other"}'), 'signature-a');

    // Assert
    should(native).equal('native:ZXZ0X25hdGl2ZQ');
    should(fallback).not.equal(changedSignature);
    should(fallback).not.equal(changedBody);
    should(fallback).match(/^sha256:[a-f0-9]{64}$/);
  });
});

describe('retry policy', () => {
  it('should move from seconds through minutes to hours and cap each delay', () => {
    // Arrange
    const base = {
      createdAtMs: 0,
      nowMs: 0,
      retryWindowMs: 72 * 60 * 60 * 1_000,
    };

    // Act
    const seconds = nextRetry({ ...base, attemptNumber: 1 });
    const minutes = nextRetry({ ...base, attemptNumber: 8 });
    const hours = nextRetry({ ...base, attemptNumber: 20 });

    // Assert
    should(seconds).deepEqual({
      kind: 'retry',
      delayMs: 5_000,
      dueAtMs: 5_000,
    });
    should(minutes.kind === 'retry' ? minutes.delayMs : 0).equal(640_000);
    should(hours.kind === 'retry' ? hours.delayMs : 0).equal(6 * 60 * 60 * 1_000);
  });

  it('should exhaust a tenant-shortened window and cap oversized configuration at 72 hours', () => {
    // Arrange
    const shortenedWindowMs = 30_000;

    // Act
    const shortened = nextRetry({
      attemptNumber: 4,
      createdAtMs: 0,
      nowMs: 0,
      retryWindowMs: shortenedWindowMs,
    });
    const bounded = boundedRetryWindowMs(10 * 24 * 60 * 60 * 1_000);

    // Assert
    should(shortened).deepEqual({ kind: 'dead-letter' });
    should(bounded).equal(72 * 60 * 60 * 1_000);
  });
});

describe('InternalDeliverySigner', () => {
  it('should sign each timestamp freshly and reject forged or stale signatures', () => {
    // Arrange
    const subject = new InternalDeliverySigner();
    const body = encoder.encode('raw-provider-body');
    const secret = encoder.encode('internal-signing-secret');

    // Act
    const first = subject.sign(body, secret, 1_000);
    const retry = subject.sign(body, secret, 1_001);
    const firstValid = subject.verify(first.header, body, secret, 1_000);
    const retryValid = subject.verify(retry.header, body, secret, 1_001);
    const forgedValid = subject.verify(first.header, encoder.encode('forged'), secret, 1_000);
    const staleValid = subject.verify(first.header, body, secret, 1_301);

    // Assert
    should(first.header).not.equal(retry.header);
    should(firstValid).be.true();
    should(retryValid).be.true();
    should(forgedValid).be.false();
    should(staleValid).be.false();
  });

  it('should accept optional whitespace but reject duplicate or unknown signature parameters', () => {
    // Arrange
    const subject = new InternalDeliverySigner();
    const body = encoder.encode('canonical-body');
    const secret = encoder.encode('internal-signing-secret');
    const signed = subject.sign(body, secret, 1_000);
    const digest = signed.header.slice(signed.header.indexOf('v1=') + 3);

    // Act
    const reordered = subject.verify(` v1 = ${digest}\t,\tt = 1000 `, body, secret, 1_000);
    const duplicate = subject.verify(`t=1000,t=1000,v1=${digest}`, body, secret, 1_000);
    const unknown = subject.verify(`t=1000,x=${digest}`, body, secret, 1_000);

    // Assert
    should(reordered).be.true();
    should(duplicate).be.false();
    should(unknown).be.false();
  });
});
