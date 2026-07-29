export type ManagementErrorCode =
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'invalid'
  | 'immutable_home'
  | 'rate_limited'
  | 'unavailable'
  | 'compiler_failed';

export class ManagementError extends Error {
  public constructor(
    public readonly code: ManagementErrorCode,
    message: string,
    public readonly details?: Readonly<Record<string, unknown>>,
  ) {
    super(message);
    this.name = 'ManagementError';
  }
}

export function isManagementError(error: unknown): error is ManagementError {
  return error instanceof ManagementError;
}
