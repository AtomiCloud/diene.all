type PortName = 'system' | 'vfs' | 'terminal' | 'logging' | 'metrics';

type PortErrorCode =
  | 'already-exists'
  | 'closed'
  | 'directory-not-empty'
  | 'invalid-input'
  | 'io'
  | 'not-a-directory'
  | 'not-a-file'
  | 'not-found'
  | 'permission-denied'
  | 'timeout'
  | 'unavailable'
  | 'unexpected-call'
  | 'unsupported';

type PortErrorDetails = Readonly<Record<string, unknown>>;

const PORT_ERROR_BRAND = Symbol.for('AtomiCloud.Diene.Interfaces.PortError');

class PortError<P extends PortName = PortName> extends Error {
  readonly _tag = 'PortError' as const;
  readonly details: PortErrorDetails;

  static override [Symbol.hasInstance](value: unknown): boolean {
    return (
      typeof value === 'object' &&
      value !== null &&
      (value as { readonly [PORT_ERROR_BRAND]?: unknown })[PORT_ERROR_BRAND] === true
    );
  }

  constructor(
    readonly port: P,
    readonly code: PortErrorCode,
    readonly operation: string,
    message: string,
    details: PortErrorDetails = {},
  ) {
    super(message);
    this.name = 'PortError';
    this.details = Object.freeze({ ...details });
    Object.defineProperty(this, PORT_ERROR_BRAND, { value: true });
  }
}

type SystemError = PortError<'system'>;
type VfsError = PortError<'vfs'>;
type TerminalError = PortError<'terminal'>;
type LoggingError = PortError<'logging'>;
type MetricsError = PortError<'metrics'>;

function portError<P extends PortName>(
  port: P,
  code: PortErrorCode,
  operation: string,
  message: string,
  details: PortErrorDetails = {},
): PortError<P> {
  return new PortError(port, code, operation, message, details);
}

export type {
  LoggingError,
  MetricsError,
  PortErrorCode,
  PortErrorDetails,
  PortName,
  SystemError,
  TerminalError,
  VfsError,
};
export { PortError, portError };
