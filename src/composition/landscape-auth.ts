import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { ConsoleAuthorizedPrincipal, ConsoleCapability } from '../console/index.ts';
import type { ConsoleNativeAuthorizer } from '../console/ports.ts';
import type {
  LandscapeAuthenticationFailure,
  LandscapeOperationsAuthenticator,
  LandscapeOperationsAuthorization,
  LandscapeOperationsCapability,
} from '../http/landscape/index.ts';

const capabilities: readonly LandscapeOperationsCapability[] = [
  'operations:read',
  'events:replay',
  'endpoints:replay',
  'endpoints:reenable',
  'retention:run',
];

/** Verifies one short-lived console-native bearer for the local landscape API. */
export class ConsoleLandscapeOperationsAuthenticator implements LandscapeOperationsAuthenticator {
  constructor(
    readonly landscape: string,
    readonly authorizer: ConsoleNativeAuthorizer,
  ) {}

  async authenticate(
    request: Request,
  ): Promise<Result<LandscapeOperationsAuthorization, LandscapeAuthenticationFailure>> {
    const authorization = request.headers.get('authorization') ?? undefined;
    const granted: LandscapeOperationsCapability[] = [];
    let principal: ConsoleAuthorizedPrincipal | undefined;
    let unavailable = false;

    for (const capability of capabilities) {
      const result = await this.authorizer.authorize(authorization, {
        landscape: this.landscape,
        capability: capability as ConsoleCapability,
      });
      if (result.ok) {
        principal ??= result.value;
        granted.push(capability);
      } else if (result.error.kind === 'unavailable' || result.error.kind === 'unexpected') {
        unavailable = true;
      }
    }

    if (principal === undefined || granted.length === 0) {
      return Err({
        code: unavailable ? 'unavailable' : 'invalid',
        message: unavailable ? 'console-native authorization is unavailable' : 'console-native bearer is invalid',
      });
    }

    return Ok({
      subject: principal.sessionId,
      accountId: principal.accountId,
      tenants: principal.scope.tenants,
      capabilities: granted,
    });
  }
}
