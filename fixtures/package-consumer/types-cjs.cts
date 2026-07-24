import { defaultOtelBlock, otelBlockSchema, type OtelBlock } from '@atomicloud/diene.otel';
import { InMemoryTraceEmitter } from '@atomicloud/diene.otel/test-helper';

function resolveThroughRequireTypes(): void {
  // Root entry: the engine-owned schema, its default block, and inferred types all
  // resolve through the require condition (.d.cts).
  const block: OtelBlock = otelBlockSchema.parse(defaultOtelBlock);

  // test-helper entry: the language-local trace double (RB-19) resolves through the
  // require condition of the /test-helper subpath.
  const traceEmitter: typeof InMemoryTraceEmitter = InMemoryTraceEmitter;

  void [block, traceEmitter];
}

void resolveThroughRequireTypes;
