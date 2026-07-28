# Platinum baseline

Platinum (element name for kgateway) is the platform Gateway API ingress chart. It is a
materialized chart product: it inherits the helm-wrapper _shape_ — two-dimension stacked values,
generated schema, the rendered-manifest validation stage, fullname and LPSM label conventions, and
the dual publish modes — but carries no CyanPrint probe matrix. Evidence is an ordinary testing
pyramid: unit tier is lint/render/schema/static conformance (including the inherited VAP stage with
one wiring sabotage); the integration tier installs on ephemeral k3d with the live kgateway control
plane.

## What platinum wraps

The chart vendors two pinned upstreams from `oci://cr.kgateway.dev/kgateway-dev/charts`:

- `kgateway` (alias `upstream`) — the Envoy-based Gateway API control plane.
- `kgateway-crds` — the `gateway.kgateway.dev/*` custom resources.

Both dependencies are `enabled: false` by default. Unit-tier static checks render platinum-owned
objects only; the k3d integration tier flips `upstream.enabled=true` (and applies the standard
Gateway API CRDs, which deploy separately from kgateway-crds) so the shared Gateway reaches
`Programmed=True`.

## Rendering model

Two independent stacked dimensions, inherited from helm-wrapper:

1. `chart/values.yaml` — platform/service/module/layer defaults (`sulfoxide` / `platinum` / `gateway` / `1`).
2. `chart/values.<landscape>.yaml` — landscape identity and provider behavior.
3. `chart/values.<cluster>.yaml` — normally-thin cluster identity.

The sample stacks are `values.yaml → values.example.yaml → values.lapras.yaml` (ordinary local),
`values.yaml → values.example.yaml → values.aws.yaml|values.oci.yaml|values.digitalocean.yaml`
(representative provider overlays), and `values.yaml → values.entei.yaml` (the ENTEI dev-host
overlay). Landscape, cluster, and provider overlays remain independently stackable. Platinum is
config-free and ExternalSecret-free, so there is no build-phase config vendoring and no pre-sync
migration hook.

## Identity and naming

- `labelPrefix` is the only prefix input (`atomi.cloud`); every service-tree label and annotation helper reads it.
- LPSM is `{landscape, platform, service, module}`; the platform slot always comes from the release namespace (`sulfoxide`).
- Resource names use `<service>-<token>` with exactly one dash, always via the fullname helper: `platinum-edge` (LoadBalancer), `platinum-gateway` (Gateway), `platinum-health` (HTTPRoute), `platinum-api` (the health backend, the chart's primary workload), `platinum-certprimary` / `platinum-certbackup` (registered-fleet wildcard Certificates). The cluster-scoped `GatewayClass` is the bare classname `platinum`.

## Gateway API edge

Platinum owns one shared edge per target cluster:

- A `GatewayClass` named `platinum` bound to v2.2.9's real controller,
  `kgateway.dev/kgateway`. The schema pins this value and the live adoption is verified in k3d.
- One shared `Gateway` (`platinum-gateway`) with HTTP plus terminating HTTPS listeners for the
  selected primary and backup registered-fleet wildcard domains.
- The LoadBalancer `Service` (`platinum-edge`), `type: LoadBalancer`, selecting the proxy generated
  for `platinum-gateway` through kgateway v2.2.9's exact three stable labels. Its numeric
  `targetPort`s 80 and 443 match the generated proxy listener container ports. A checked-in
  v2.2.9 proxy golden and the enabled upstream render guard this binding; missing/mismatched
  selector or port values fail rendering.

### Per-provider fixed-IP LoadBalancer annotations

The cloud load balancer is the sole public origin mode. NodePort and hostPort are absent and a
reappearing NodePort surface trips the inherited VAP stage (this is platinum's one Q-G20 wiring
sabotage; per-rule proof lives in charts/vap-policies).

- AWS NLB: deterministic subnet list paired positionally with Elastic IP allocation ids (`service.beta.kubernetes.io/aws-load-balancer-subnets` + `...-eip-allocations`). This path carries the standing EKS Auto Mode compatibility assumption until the live test completes.
- OCI: reserved public IP annotation (`oci.oraclecloud.com/reserved-ips`).
- DigitalOcean: provider-lifetime-stable load balancer IP, with no fixed-IP annotation.

## Health endpoint

Every gateway exposes `/healthz` and must return 2xx. This is the target the traffic controller's
unified 5s poll hits once per cluster per tick; its liveness stamps
`ClusterRegistration.status.acceptingTraffic`. Platinum renders an `HTTPRoute` (`platinum-health`)
that pins the `/healthz` path and routes to the platinum-owned health backend (`platinum-api`).
Chart scope stops at "route rendered + 2xx in k3d"; the runtime poll cadence and stale-tick paging
are traffic-controller behavior.

## Registered-fleet certificates

Platinum issues the registered-fleet wildcard `Certificate`s against zinc's DNS-01 `ClusterIssuer`
definition (owned by charts/zinc and instantiated once per cluster — one definition, not per
landscape):

- `platinum-certprimary` — the primary base-domain wildcard.
- `platinum-certbackup` — the second R53 base-domain wildcard for cluster-endpoint failover TLS (S8 backup domain).

Each wildcard is present in the Certificate's `dnsNames` SAN list (the apex may be an additional
SAN). The shared Gateway consumes the matching generated Secrets through two explicit HTTPS
listeners with `tls.mode: Terminate`; a missing wildcard SAN or broken Secret reference is a unit
test failure.

Zinc remains the issuer-definition owner. Platinum neither hand-authors nor infers per-host
Certificates from Gateway listeners. Exact-host TLS ownership (one exact-name `Certificate` per
approved Garden hostname, one-label wildcards rejected as coverage for a dotted hostname) belongs to
the exposure-materializer, not this chart.

## ENTEI dev-host overlay

`values.entei.yaml` selects `devHost.enabled: true`. In this mode platinum renders the shared
`GatewayClass`, the shared `Gateway`, and the provider `LoadBalancer` only. The exact rendered
object-set assertion rejects any additional object, including the ordinary health Deployment and
its ClusterIP Service. Per-host `Certificate`,
`ListenerSet`, and `HTTPRoute` are owned by the exposure materializer; this chart renders none of
them, and the registered-fleet Certificates are disabled because ENTEI's exact-name certs come from
the materializer. Garden submits the narrow owner-scoped exposure claim and needs no general ENTEI
kubeconfig. ENTEI itself remains a registered, infrastructure-only, `traffic=false` host; this chart
does not add it to any workload roster.

## Publishing

OCI is the default publish/consume mode. Git chart repositories remain secondary.
`scripts/release/bump.sh` stamps `chart/Chart.yaml` at the release commit; `scripts/ci/publish.sh`
refuses a manifest/tag mismatch, regenerates Helm docs, and supports git packaging plus OCI dry-run
or push. No external publish is needed for local proof.

## Tokenization surface

Tokenize these isolated scalars when materializing an instance:

- chart and release name;
- `serviceTree` platform/service/module/layer values;
- `labelPrefix`;
- upstream chart name/version/repository (kgateway + kgateway-crds) and vendored archive filenames;
- upstream kgateway image references used by `latest`;
- the GatewayClass name and controllerName binding;
- OCI organization/repository path and secondary git repository URL;
- landscape and cluster overlay filenames;
- k3d cluster and local registry names;
- repository-qualified physical instance id, normalized DNS label, and original-id annotation;
- selected hostname zone;
- the registered-fleet base-domain wildcards and the zinc ClusterIssuer name;
- per-provider LoadBalancer annotation keys and fixed-IP allocation values.

## Held boundaries

The full k3d integration tier (Gateway `Programmed=True`, real proxy Endpoints, live `/healthz` 2xx
through a LoadBalancer ingress or isolated k3d host endpoint, and a durable local OCI round-trip
archive + SHA-256), the ENTEI exact-host TLS integration
scenarios, the `ListenerSet` API-version pin, and the final landscape/profile roster remain reserved
for the serialized proof window or their owning nodes.
