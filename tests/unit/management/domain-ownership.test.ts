import { describe, expect, test } from 'bun:test';
import { sha256 } from '../../../src/management/crypto.ts';
import { DnsDomainOwnershipVerifier } from '../../../src/management/domain-ownership.ts';

const input = {
  hostname: 'hooks.acme.example',
  intakeTarget: 'hooks.mercury.p.mew.cluster.atomi.cloud',
  challengeTarget:
    'mercury-domain-00000000-0000-4000-8000-000000000001.domain-validation.hooks.mercury.p.mew.cluster.atomi.cloud',
  certificateSecretPointer: '/mercury-domain-tls',
};

async function verificationInput() {
  return {
    ...input,
    expectedTokenHash: await sha256(input.challengeTarget),
  };
}

describe('DNS custom-domain ownership verifier', () => {
  test('requires both exact CNAMEs and normalizes answer case plus one trailing dot', async () => {
    const queries: string[] = [];
    const verifier = new DnsDomainOwnershipVerifier({
      resolver: {
        async resolveCname(name) {
          queries.push(name);
          return name.startsWith('_acme-challenge.')
            ? [`${input.challengeTarget.toUpperCase()}.`]
            : [`${input.intakeTarget.toUpperCase()}.`];
        },
      },
      certificateReadiness: {
        async isReady(readinessInput) {
          expect(readinessInput).toEqual({
            hostname: input.hostname,
            certificateSecretPointer: input.certificateSecretPointer,
          });
          return true;
        },
      },
    });

    expect(await verifier.verify(await verificationInput())).toEqual({ owned: true, certificateReady: true });
    expect(queries).toEqual([input.hostname, `_acme-challenge.${input.hostname}`]);
  });

  test('rejects empty, multiple, conflicting, malformed, and hash-unbound answers', async () => {
    for (const answers of [
      [],
      [input.intakeTarget, input.intakeTarget],
      ['attacker.example'],
      [` ${input.intakeTarget}`],
    ]) {
      let readinessChecks = 0;
      const verifier = new DnsDomainOwnershipVerifier({
        resolver: {
          async resolveCname(name) {
            return name.startsWith('_acme-challenge.') ? [input.challengeTarget] : answers;
          },
        },
        certificateReadiness: {
          async isReady() {
            readinessChecks += 1;
            return true;
          },
        },
      });
      expect(await verifier.verify(await verificationInput())).toEqual({ owned: false, certificateReady: false });
      expect(readinessChecks).toBe(0);
    }

    const verifier = new DnsDomainOwnershipVerifier({
      resolver: {
        async resolveCname(name) {
          return name.startsWith('_acme-challenge.') ? [input.challengeTarget] : [input.intakeTarget];
        },
      },
      certificateReadiness: {
        async isReady() {
          return true;
        },
      },
    });
    expect(
      await verifier.verify({
        ...(await verificationInput()),
        expectedTokenHash: await sha256('different-target.example'),
      }),
    ).toEqual({ owned: false, certificateReady: false });
  });

  test('keeps DNS and certificate-reader failures unavailable and readiness false unpublished', async () => {
    const failingDns = new DnsDomainOwnershipVerifier({
      resolver: {
        async resolveCname() {
          throw new Error('resolver timeout');
        },
      },
      certificateReadiness: {
        async isReady() {
          return true;
        },
      },
    });
    await expect(failingDns.verify(await verificationInput())).rejects.toMatchObject({
      code: 'unavailable',
      details: { cause: 'resolver timeout' },
    });

    const notReady = new DnsDomainOwnershipVerifier({
      resolver: {
        async resolveCname(name) {
          return name.startsWith('_acme-challenge.') ? [input.challengeTarget] : [input.intakeTarget];
        },
      },
      certificateReadiness: {
        async isReady() {
          return false;
        },
      },
    });
    expect(await notReady.verify(await verificationInput())).toEqual({ owned: true, certificateReady: false });

    const failingCertificate = new DnsDomainOwnershipVerifier({
      resolver: {
        async resolveCname(name) {
          return name.startsWith('_acme-challenge.') ? [input.challengeTarget] : [input.intakeTarget];
        },
      },
      certificateReadiness: {
        async isReady() {
          throw new Error('certificate store unavailable');
        },
      },
    });
    await expect(failingCertificate.verify(await verificationInput())).rejects.toMatchObject({
      code: 'unavailable',
      details: { cause: 'certificate store unavailable' },
    });
  });
});
