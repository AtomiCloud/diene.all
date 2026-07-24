# API client standard

Api clients use one immutable registration list. Every backend owns one LPSM
coordinate, one configuration-derived base URL, one auth resource, and one
`IAuth` binding. Runtime calls cannot replace the hostname or select a physical
cluster URL.

## Register backends

Register api-engine Problems in the application's existing registry. Validate
each engine-owned block as part of the application config root, then construct
the complete tree once:

```ts
import {
  apiEngineConfigBlockSchema,
  createApiEngine,
  OPAQUE_NETWORK_RETRY_ONCE,
  registerApiProblems,
  type IAuth,
} from '@atomicloud/diene.api-engine';

const ordersAuth: IAuth = authStateRetriever;
const orders = apiEngineConfigBlockSchema.parse({
  coordinate: config.orders.coordinate,
  baseUrl: config.orders.baseUrl,
  resource: config.orders.resource,
  timeoutMs: config.orders.timeoutMs,
  retry: OPAQUE_NETWORK_RETRY_ONCE,
  auth: ordersAuth,
  createClient: ({ baseUrl, fetch }) => createOrdersClient({ baseUrl, fetch }),
  rescue: {
    enabled: runtimeContext.rescueEnabled,
    trip: rescueRouter.trip,
  },
});

const engine = registerApiProblems(problemRegistry).andThen(problems =>
  createApiEngine({ problems, bindings: [orders] }),
);
```

The retry profile is fixed: only an opaque network failure without a received
HTTP status gets one retry, using a fresh `Request`. Rescue is an injected trip
point after both opaque attempts fail; api-engine does not implement routing.

## Call through Result

Resolve the typed client and call its Kiota-shaped namespaces through `Result`:

```ts
const order = engine
  .andThen(tree => tree.resolve<OrdersClient>(config.orders.coordinate))
  .andThen(client => client.orders.byId('42').get());

await order.match({
  ok: value => renderOrder(value),
  err: problem => renderProblem(problem),
});
```

Every proxied SDK method returns `Result<T, Problem>` and does not reject. Use
`match`, `map`, or `andThen`; do not use throwing `unwrap` in runtime code.

When adapting a raw SDK value outside the proxy, call `toResult(value, context)`.
The `isProblem`, `isProblemDetail`, and `isResponse` guards are also public;
Problem recognition delegates to `@atomicloud/diene.problems`.
