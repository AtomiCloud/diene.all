import { resolveCname } from 'node:dns/promises';
import { sha256 } from './crypto.ts';
import { ManagementError } from './errors.ts';

export interface DomainOwnershipVerificationInput {
  hostname: string;
  intakeTarget: string;
  challengeTarget: string;
  certificateSecretPointer: string;
  expectedTokenHash: string;
}

export interface DomainOwnershipVerifier {
  verify(input: DomainOwnershipVerificationInput): Promise<{ owned: boolean; certificateReady: boolean }>;
}

export interface DomainCnameResolver {
  resolveCname(name: string): Promise<readonly string[]>;
}

export interface DomainCertificateReadinessProbe {
  isReady(input: { hostname: string; certificateSecretPointer: string }): Promise<boolean>;
}

export interface DnsDomainOwnershipVerifierOptions {
  resolver?: DomainCnameResolver;
  certificateReadiness: DomainCertificateReadinessProbe;
}

const defaultResolver: DomainCnameResolver = { resolveCname };
const DNS_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

function canonicalDnsTarget(value: string): string | undefined {
  if (value !== value.trim()) return undefined;
  const normalized = value.toLowerCase().replace(/\.$/, '');
  const labels = normalized.split('.');
  if (
    normalized.length === 0 ||
    normalized.length > 253 ||
    labels.length < 2 ||
    labels.some(label => !DNS_LABEL.test(label))
  ) {
    return undefined;
  }
  return normalized;
}

function oneCanonicalAnswer(answers: readonly string[]): string | undefined {
  if (answers.length !== 1) return undefined;
  const answer = answers[0];
  return answer === undefined ? undefined : canonicalDnsTarget(answer);
}

export class DnsDomainOwnershipVerifier implements DomainOwnershipVerifier {
  readonly #resolver: DomainCnameResolver;
  readonly #certificateReadiness: DomainCertificateReadinessProbe;

  public constructor(options: DnsDomainOwnershipVerifierOptions) {
    this.#resolver = options.resolver ?? defaultResolver;
    this.#certificateReadiness = options.certificateReadiness;
  }

  public async verify(input: DomainOwnershipVerificationInput): Promise<{ owned: boolean; certificateReady: boolean }> {
    const hostname = canonicalDnsTarget(input.hostname);
    const intakeTarget = canonicalDnsTarget(input.intakeTarget);
    const challengeTarget = canonicalDnsTarget(input.challengeTarget);
    if (
      hostname === undefined ||
      intakeTarget === undefined ||
      challengeTarget === undefined ||
      (await sha256(input.challengeTarget)) !== input.expectedTokenHash
    ) {
      return { owned: false, certificateReady: false };
    }

    let trafficAnswers: readonly string[];
    let challengeAnswers: readonly string[];
    try {
      [trafficAnswers, challengeAnswers] = await Promise.all([
        this.#resolver.resolveCname(hostname),
        this.#resolver.resolveCname(`_acme-challenge.${hostname}`),
      ]);
    } catch (error) {
      throw new ManagementError('unavailable', 'custom domain DNS ownership lookup failed', {
        cause: error instanceof Error ? error.message : String(error),
      });
    }

    if (
      oneCanonicalAnswer(trafficAnswers) !== intakeTarget ||
      oneCanonicalAnswer(challengeAnswers) !== challengeTarget
    ) {
      return { owned: false, certificateReady: false };
    }

    try {
      return {
        owned: true,
        certificateReady: await this.#certificateReadiness.isReady({
          hostname,
          certificateSecretPointer: input.certificateSecretPointer,
        }),
      };
    } catch (error) {
      throw new ManagementError('unavailable', 'custom domain certificate readiness check failed', {
        cause: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
