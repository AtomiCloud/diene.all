import type { OtelRuntime } from '@atomicloud/diene.e2e/otel';

export type ApplicationTracer = OtelRuntime['tracer'];

export async function withAdapterSpan<T>(
  tracer: ApplicationTracer,
  name: string,
  attributes: Readonly<Record<string, boolean | number | string>>,
  operation: () => Promise<T>,
): Promise<T> {
  return tracer.startActiveSpan(name, async span => {
    span.setAttributes(attributes);
    try {
      const value = await operation();
      span.setStatus({ code: 1 });
      return value;
    } catch (error) {
      span.recordException(error instanceof Error ? error : String(error));
      span.setStatus({ code: 2, message: error instanceof Error ? error.message : String(error) });
      throw error;
    } finally {
      span.end();
    }
  });
}
