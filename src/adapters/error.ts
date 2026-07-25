export class AdapterError extends Error {
  constructor(
    readonly operation: string,
    message: string,
    override readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'AdapterError';
  }
}
