# diene.api-engine patterns

## Register once

```ts
const engine = registerApiProblems(problemRegistry).andThen(problems => createApiEngine({ problems, bindings }));
```

Keep `bindings` immutable and complete. A binding owns exactly one LPSM address,
one configured hostname, one auth retriever, and one canonical auth resource.
Never accept a base URL from an invocation.

## Wire a Kiota SDK

```ts
const binding = {
  coordinate: { landscape, platform, service, module },
  baseUrl: config.ordersApiUrl,
  resource: config.ordersResource,
  auth: ordersAuthState,
  createClient: ({ baseUrl, fetch }) => createOrdersClient({ baseUrl, fetch }),
};
```

The client only needs to be structurally Kiota-shaped: synchronous construction,
namespace objects, and methods returning values, promises, or `Response` objects.

## Handle Results

Resolve and call with `andThen`:

```ts
const order = engine
  .andThen(ready => ready.resolve<OrdersClient>(ordersCoordinate))
  .andThen(client => client.orders.byId('42').get());
```

Treat the `Problem` as the only failure channel. Do not add `try/catch` around a
proxied SDK call and do not call throwing `unwrap` in runtime code.

## Rescue trips

Set `rescue.enabled` explicitly and implement only `trip(context)`. The callback
runs after two consecutive opaque, no-status transport failures. It never runs
for a received HTTP status, a timeout, an abort, or a successful retry. Route or
fail over in the application; api-engine deliberately owns no rescue router.

## TestHelper

Use `FakeAuthStateRetriever`, `createScriptedKiotaClient`, response builders, and
Problem assertions from the `/test-helper` subpath. Build canonical resource keys
with `canonicalTestResource` so multi-backend token fixtures match auth-engine.
