import { CONSOLE_SCRIPT, CONSOLE_STYLES } from './assets.ts';
import type {
  ConsoleActionReceipt,
  ConsoleCapability,
  ConsoleDashboardSnapshot,
  ConsoleEndpointReplayTarget,
  ConsoleEventDetail,
  ConsoleFailure,
  ConsoleFilterOption,
  ConsoleFilters,
  ConsoleIdentity,
} from './model.ts';

export const escapeHtml = (value: string): string =>
  value.replace(
    /[&<>'"]/g,
    character =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        "'": '&#39;',
        '"': '&quot;',
      })[character] ?? character,
  );

const pathSegment = (value: string): string => encodeURIComponent(value);

const timestamp = (value: Date | undefined, empty = 'NO SIGNAL'): string =>
  value === undefined
    ? `<span class="muted">${empty}</span>`
    : `<time datetime="${escapeHtml(value.toISOString())}" data-relative-time>${escapeHtml(
        value.toISOString().replace('T', ' ').replace('.000Z', 'Z'),
      )}</time>`;

const formatNumber = (value: number, maximumFractionDigits = 0): string =>
  new Intl.NumberFormat('en-US', { maximumFractionDigits }).format(value);

const percentage = (value: number): string => `${formatNumber(value * 100, 1)}%`;

const duration = (seconds: number): string => {
  if (seconds < 60) return `${formatNumber(seconds)}s`;
  if (seconds < 3_600) return `${formatNumber(seconds / 60, 1)}m`;
  return `${formatNumber(seconds / 3_600, 1)}h`;
};

const bytes = (value: number): string => {
  if (value < 1_024) return `${formatNumber(value)} B`;
  if (value < 1_048_576) return `${formatNumber(value / 1_024, 1)} KiB`;
  if (value < 1_073_741_824) return `${formatNumber(value / 1_048_576, 1)} MiB`;
  return `${formatNumber(value / 1_073_741_824, 1)} GiB`;
};

const stateTone = (state: string): string => {
  const good = ['healthy', 'closed', 'current', 'within-limit', 'delivered', 'visible', 'active'];
  const warning = [
    'degraded',
    'half-open',
    'compiling',
    'approaching',
    'retrying',
    'queued',
    'delivering',
    'delayed',
    'withheld',
    'withheld-d11',
  ];
  const bad = ['critical', 'open', 'failed', 'stale', 'exhausted', 'dead-lettered', 'blocked', 'orphaned-provider'];

  if (good.includes(state)) return 'good';
  if (warning.includes(state)) return 'warn';
  if (bad.includes(state)) return 'bad';
  return 'quiet';
};

const stateChip = (state: string): string =>
  `<span class="state state--${stateTone(state)}"><span aria-hidden="true" class="state__pip"></span>${escapeHtml(
    state.replaceAll('-', ' ').toUpperCase(),
  )}</span>`;

const documentHead = (title: string, nonce: string): string => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark">
  <meta name="theme-color" content="#090b0a">
  <title>${escapeHtml(title)} · Mercury</title>
  <style nonce="${escapeHtml(nonce)}">${CONSOLE_STYLES}</style>
</head>`;

const documentTail = (nonce: string): string =>
  `<script nonce="${escapeHtml(nonce)}" type="module">${CONSOLE_SCRIPT}</script></body></html>`;

interface ShellInput {
  readonly title: string;
  readonly eyebrow: string;
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly generatedAt?: Date;
  readonly body: string;
}

const shell = (input: ShellInput): string => `${documentHead(input.title, input.nonce)}
<body>
<a class="skip-link button" href="#main">Skip to operations</a>
<div class="shell">
  <aside class="rail" aria-label="Console context">
    <div>
      <p class="brand">Mer<span>cury</span></p>
      <p class="brand-code">WHK / CONTROL SURFACE</p>
    </div>
    <nav class="rail__nav" aria-label="Operations sections">
      <a href="/console#intake">01 / Intake</a>
      <a href="/console#delivery">02 / Delivery</a>
      <a href="/console#events">03 / Event ledger</a>
      <a href="/console#dlq">04 / Dead letters</a>
      <a href="/console#routes">05 / Route registry</a>
      <a href="/console#configuration">06 / Configuration</a>
      <a href="/console#archive">07 / Archive</a>
      <a href="/console#quota">08 / Quota</a>
    </nav>
    <div class="account">
      <div class="account__kind">${
        input.identity.accountKind === 'default-internal'
          ? 'Default internal account'
          : input.identity.accountKind === 'internal'
            ? 'Internal account'
            : 'External account'
      }</div>
      <p class="account__name">${escapeHtml(input.identity.accountName)}</p>
      <p class="account__user">Account ID · ${escapeHtml(input.identity.accountId)}</p>
      <form method="post" action="/console/logout">
        <input type="hidden" name="csrf" value="${escapeHtml(input.csrfToken)}">
        <button class="button--ghost" type="submit">End session</button>
      </form>
    </div>
  </aside>
  <main class="workspace" id="main" tabindex="-1">
    <header class="mast">
      <div>
        <p class="eyebrow">${escapeHtml(input.eyebrow)}</p>
        <h1>${escapeHtml(input.title)}</h1>
      </div>
      <div class="mast__time">
        <strong data-live-clock>${escapeHtml(
          (input.generatedAt ?? new Date(0)).toISOString().slice(11, 19),
        )} UTC</strong>
        <span>${
          input.generatedAt === undefined
            ? 'Secure product console'
            : `Fan-in ${escapeHtml(input.generatedAt.toISOString())}`
        }</span>
      </div>
    </header>
    ${input.body}
  </main>
</div>
${documentTail(input.nonce)}`;

export interface LoginViewInput {
  readonly nonce: string;
  readonly csrfToken: string;
  readonly accountName?: string;
  readonly failure?: ConsoleFailure;
}

export const renderLogin = (input: LoginViewInput): string => `${documentHead('Sign in', input.nonce)}
<body>
<a class="skip-link button" href="#login">Skip to sign in</a>
<main class="login-shell">
  <section class="login-mark" aria-labelledby="product-name">
    <div>
      <p class="brand" id="product-name">Mer<span>cury</span></p>
      <p class="brand-code">Multi-landscape webhook operations</p>
    </div>
    <p class="login-mark__copy">One account-backed surface for fleet operators and external tenants. Sessions stay here; operational calls are exchanged server-side for scoped native authorization.</p>
  </section>
  <section class="login-panel" aria-labelledby="login-title">
    <form class="login-form" id="login" method="post" action="/console/login">
      <p class="eyebrow">Identity checkpoint / TLS required</p>
      <h1 id="login-title">Open the control room</h1>
      <p class="login-form__intro">Use a Mercury account name and its native management credential. Fleet operators enter through <code>internal/default</code>—there is no separate admin door.</p>
      ${
        input.failure === undefined
          ? ''
          : `<div class="notice notice--bad" role="alert"><strong class="notice__code">AUTH</strong><p><strong>${escapeHtml(
              input.failure.title,
            )}</strong><br>${escapeHtml(input.failure.detail)}</p></div>`
      }
      <input type="hidden" name="csrf" value="${escapeHtml(input.csrfToken)}">
      <div class="field">
        <label for="account-name">Account name</label>
        <input id="account-name" name="accountName" type="text" value="${escapeHtml(
          input.accountName ?? '',
        )}" autocomplete="username" maxlength="256" placeholder="internal/default" required autofocus>
      </div>
      <div class="field">
        <label for="bearer-credential">Native bearer credential</label>
        <input id="bearer-credential" name="bearerCredential" type="password" autocomplete="current-password" minlength="16" maxlength="512" required aria-describedby="credential-help">
        <p class="form-help" id="credential-help">Verified once against Mercury management. The credential is never stored in the console session, rendered into HTML, or forwarded in a browser cookie.</p>
      </div>
      <button type="submit">Authenticate account</button>
    </form>
  </section>
</main>
${documentTail(input.nonce)}`;

export interface PublicFailureViewInput {
  readonly nonce: string;
  readonly title: string;
  readonly detail: string;
  readonly requestId?: string;
}

export const renderPublicFailure = (input: PublicFailureViewInput): string => `${documentHead(input.title, input.nonce)}
<body>
<main class="login-shell">
  <section class="login-mark" aria-labelledby="product-name">
    <div>
      <p class="brand" id="product-name">Mer<span>cury</span></p>
      <p class="brand-code">Operations boundary / safe failure</p>
    </div>
    <p class="login-mark__copy">The console did not expose request, session, or native authorization data while handling this response.</p>
  </section>
  <section class="login-panel" aria-labelledby="failure-title">
    <div class="login-form">
      <span class="result-mark result-mark--bad" aria-hidden="true">!</span>
      <p class="eyebrow">Control surface response</p>
      <h1 id="failure-title">${escapeHtml(input.title)}</h1>
      <p role="alert">${escapeHtml(input.detail)}</p>
      ${
        input.requestId === undefined
          ? ''
          : `<p class="form-help">Request reference: ${escapeHtml(input.requestId)}</p>`
      }
      <p><a class="button button--ghost" href="/console/login">Return to sign in</a></p>
    </div>
  </section>
</main>
${documentTail(input.nonce)}`;

const filterOptions = (
  values: readonly ConsoleFilterOption[],
  selected: string | undefined,
  allLabel: string,
): string =>
  `<option value="">${escapeHtml(allLabel)}</option>${values
    .map(
      option =>
        `<option value="${escapeHtml(option.value)}"${
          option.value === selected ? ' selected' : ''
        }>${escapeHtml(option.label)}${option.count === undefined ? '' : ` · ${formatNumber(option.count)}`}</option>`,
    )
    .join('')}`;

const filterMatrix = (snapshot: ConsoleDashboardSnapshot, filters: ConsoleFilters): string => `
<form class="filter-matrix" method="get" action="/console" aria-label="Operational fan-in filters">
  <div class="filter-matrix__grid">
    <div><label for="landscape">Landscape</label><select id="landscape" name="landscape">${filterOptions(
      snapshot.filterOptions.landscapes,
      filters.landscape,
      'All landscapes',
    )}</select></div>
    <div><label for="tenant">Tenant</label><select id="tenant" name="tenant">${filterOptions(
      snapshot.filterOptions.tenants,
      filters.tenant,
      'All authorized tenants',
    )}</select></div>
    <div><label for="provider">Provider</label><select id="provider" name="provider">${filterOptions(
      snapshot.filterOptions.providers,
      filters.provider,
      'All providers',
    )}</select></div>
    <div><label for="endpoint">Endpoint</label><select id="endpoint" name="endpoint">${filterOptions(
      snapshot.filterOptions.endpoints,
      filters.endpoint,
      'All endpoints',
    )}</select></div>
    <div><label for="status">Status</label><select id="status" name="status">
      ${['all', 'queued', 'delivering', 'retrying', 'delivered', 'dead-lettered', 'withheld']
        .map(
          status =>
            `<option value="${status}"${status === filters.status ? ' selected' : ''}>${escapeHtml(
              status.replaceAll('-', ' '),
            )}</option>`,
        )
        .join('')}
    </select></div>
    <button type="submit">Apply matrix</button>
  </div>
</form>`;

const sectionHeading = (id: string, title: string, summary: string): string =>
  `<header class="section__heading"><h2 id="${id}-title">${escapeHtml(
    title,
  )}</h2><p>${escapeHtml(summary)}</p></header>`;

const empty = (message: string): string => `<p class="empty">${escapeHtml(message)}</p>`;

const intakeSection = (snapshot: ConsoleDashboardSnapshot): string => `
<section class="section" id="intake" aria-labelledby="intake-title">
  ${sectionHeading('intake', 'Intake pulse', `${snapshot.intake.length} landscape signals`)}
  ${
    snapshot.intake.length === 0
      ? empty('No intake telemetry matches this fan-in matrix.')
      : `<div class="telemetry-strip">${snapshot.intake
          .map(
            item => `<article class="telemetry-cell">
              <div class="telemetry-cell__top"><h3 class="telemetry-cell__name">${escapeHtml(
                item.landscape,
              )}</h3>${stateChip(item.state)}</div>
              <dl>
                <dt>Accepted / min</dt><dd>${formatNumber(item.eventsPerMinute, 1)}</dd>
                <dt>Verify failure</dt><dd>${percentage(item.verificationFailureRate)}</dd>
                <dt>Dedup hit</dt><dd>${percentage(item.dedupHitRate)}</dd>
                <dt>Last accepted</dt><dd>${timestamp(item.lastAcceptedAt)}</dd>
              </dl>
            </article>`,
          )
          .join('')}</div>`
  }
</section>`;

const deliverySection = (snapshot: ConsoleDashboardSnapshot, capabilities: readonly ConsoleCapability[]): string => `
<section class="section" id="delivery" aria-labelledby="delivery-title">
  ${sectionHeading('delivery', 'Delivery circuits', `${snapshot.deliveries.length} endpoint obligations`)}
  ${
    snapshot.deliveries.length === 0
      ? empty('No endpoint health matches this fan-in matrix.')
      : `<div class="table-wrap"><table>
        <caption>Live per-endpoint health, retry depth, lag, and circuit state. Each registration remains an independent delivery obligation.</caption>
        <thead><tr><th>Endpoint / tenant</th><th>Landscape</th><th>Provider</th><th>Status</th><th>Circuit</th><th class="numeric">Success</th><th class="numeric">Retry depth</th><th class="numeric">Lag</th><th class="numeric">DLQ</th><th>Last attempt</th><th>Controls</th></tr></thead>
        <tbody>${snapshot.deliveries
          .map(
            item => `<tr>
              <td><strong>${escapeHtml(item.endpointName)}</strong><br><span class="muted">${escapeHtml(
                item.tenant,
              )} · ${escapeHtml(item.endpointId)}</span></td>
              <td>${escapeHtml(item.landscape)}</td>
              <td>${escapeHtml(item.provider)}</td>
              <td>${stateChip(item.state)}</td>
              <td>${stateChip(item.circuit)}</td>
              <td class="numeric">${percentage(item.successRate)}</td>
              <td class="numeric">${formatNumber(item.retryDepth)}</td>
              <td class="numeric">${duration(item.lagSeconds)}</td>
              <td class="numeric">${formatNumber(item.deadLetterCount)}</td>
              <td class="nowrap">${timestamp(item.lastAttemptAt)}</td>
              <td><div class="actions">
                ${
                  capabilities.includes('endpoints:replay')
                    ? `<a class="button button--ghost" href="/console/endpoints/${pathSegment(
                        item.landscape,
                      )}/${pathSegment(item.endpointId)}/replay">Replay endpoint</a>`
                    : ''
                }
                ${
                  item.canReenable && capabilities.includes('endpoints:reenable')
                    ? `<a class="button button--danger" href="/console/endpoints/${pathSegment(
                        item.landscape,
                      )}/${pathSegment(item.endpointId)}/reenable">Re-enable</a>`
                    : ''
                }
                ${
                  !capabilities.includes('endpoints:replay') &&
                  (!item.canReenable || !capabilities.includes('endpoints:reenable'))
                    ? '<span class="muted">Read only</span>'
                    : ''
                }
              </div></td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

const routeSection = (snapshot: ConsoleDashboardSnapshot): string => `
<section class="section" id="routes" aria-labelledby="routes-title">
  ${sectionHeading('routes', 'Route registry state', `${snapshot.routes.length} compiled routes`)}
  ${
    snapshot.routes.length === 0
      ? empty('No route state matches this fan-in matrix.')
      : `<div class="table-wrap"><table>
        <caption>Compiled route state remains visible even when D11 withholds preview callback-delivery visibility.</caption>
        <thead><tr><th>Route</th><th>Landscape</th><th>Tenant</th><th>Provider</th><th>Status</th><th class="numeric">Endpoints</th><th class="numeric">Generation</th><th>Detail</th></tr></thead>
        <tbody>${snapshot.routes
          .map(
            item => `<tr>
              <td><strong>${escapeHtml(item.route)}</strong><br><span class="muted">${escapeHtml(item.routeId)}</span></td>
              <td>${escapeHtml(item.landscape)}</td>
              <td>${escapeHtml(item.tenant)}</td>
              <td>${escapeHtml(item.provider)}</td>
              <td>${stateChip(item.state)}</td>
              <td class="numeric">${formatNumber(item.endpointCount)}</td>
              <td class="numeric">${formatNumber(item.activeGeneration)}</td>
              <td>${escapeHtml(item.detail ?? 'Nominal')}</td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

const sourceFailureNotice = (snapshot: ConsoleDashboardSnapshot): string =>
  snapshot.sourceFailures.length === 0
    ? ''
    : `<div class="notice notice--bad" role="status">
      <strong class="notice__code">PARTIAL</strong>
      <div><strong>${formatNumber(snapshot.sourceFailures.length)} landscape source request(s) failed</strong>
        <ul>${snapshot.sourceFailures
          .map(
            item =>
              `<li>${escapeHtml(item.landscape)} · ${escapeHtml(item.operation)} · ${escapeHtml(item.detail)}</li>`,
          )
          .join('')}</ul>
      </div>
    </div>`;

const eventSection = (snapshot: ConsoleDashboardSnapshot, capabilities: readonly ConsoleCapability[]): string => `
<section class="section" id="events" aria-labelledby="events-title">
  ${sectionHeading('events', 'Event ledger', `${snapshot.events.length} retained events`)}
  ${
    snapshot.events.length === 0
      ? empty('No retained events match this fan-in matrix.')
      : `<div class="table-wrap"><table>
        <caption>Events remain in their landing landscape. Replay is sent back to that landscape and receives a fresh internal signature.</caption>
        <thead><tr><th>Event</th><th>Received</th><th>Landscape</th><th>Tenant</th><th>Provider / route</th><th>Endpoint</th><th>Status</th><th class="numeric">Attempts</th><th class="numeric">Lag</th><th>Next attempt</th><th>Controls</th></tr></thead>
        <tbody>${snapshot.events
          .map(
            event => `<tr>
              <td><a href="/console/events/${pathSegment(event.landscape)}/${pathSegment(
                event.id,
              )}">${escapeHtml(event.id)}</a></td>
              <td class="nowrap">${timestamp(event.receivedAt)}</td>
              <td>${escapeHtml(event.landscape)}</td>
              <td>${escapeHtml(event.tenant)}</td>
              <td>${escapeHtml(event.provider)}<br><span class="muted">${escapeHtml(event.route)}</span></td>
              <td>${escapeHtml(event.endpointName)}</td>
              <td>${stateChip(event.status)}</td>
              <td class="numeric">${formatNumber(event.attemptCount)}</td>
              <td class="numeric">${duration(event.lagSeconds)}</td>
              <td class="nowrap">${timestamp(event.nextAttemptAt, '—')}</td>
              <td><div class="actions">${
                capabilities.includes('events:replay')
                  ? `<a class="button button--ghost" href="/console/events/${pathSegment(
                      event.landscape,
                    )}/${pathSegment(event.id)}/replay">Replay event</a>`
                  : '<span class="muted">Read only</span>'
              }</div></td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

const deadLetterSection = (snapshot: ConsoleDashboardSnapshot, capabilities: readonly ConsoleCapability[]): string => `
<section class="section" id="dlq" aria-labelledby="dlq-title">
  ${sectionHeading('dlq', 'Dead-letter inspection', `${snapshot.deadLetters.length} exhausted obligations`)}
  ${
    snapshot.deadLetters.length === 0
      ? empty('No dead-lettered delivery obligations match this fan-in matrix.')
      : `<div class="table-wrap"><table>
        <caption>Delivery obligations exhausted after their tenant retry window. Replays preserve the original landing landscape.</caption>
        <thead><tr><th>Event</th><th>Endpoint</th><th>Landscape</th><th>Tenant</th><th>Provider</th><th>Exhausted</th><th>Final result</th><th class="numeric">Attempts</th><th>Controls</th></tr></thead>
        <tbody>${snapshot.deadLetters
          .map(
            item => `<tr>
              <td><a href="/console/events/${pathSegment(item.landscape)}/${pathSegment(
                item.eventId,
              )}">${escapeHtml(item.eventId)}</a></td>
              <td>${escapeHtml(item.endpointName)}</td>
              <td>${escapeHtml(item.landscape)}</td>
              <td>${escapeHtml(item.tenant)}</td>
              <td>${escapeHtml(item.provider)}</td>
              <td class="nowrap">${timestamp(item.exhaustedAt)}</td>
              <td>${escapeHtml(String(item.finalStatus))}</td>
              <td class="numeric">${formatNumber(item.attempts)}</td>
              <td><div class="actions">${
                capabilities.includes('events:replay')
                  ? `<a class="button button--ghost" href="/console/events/${pathSegment(
                      item.landscape,
                    )}/${pathSegment(item.eventId)}/replay?endpoint=${encodeURIComponent(
                      item.endpointId,
                    )}">Replay obligation</a>`
                  : '<span class="muted">Read only</span>'
              }</div></td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

const configurationSection = (snapshot: ConsoleDashboardSnapshot): string => `
<section class="section" id="configuration" aria-labelledby="configuration-title">
  ${sectionHeading('configuration', 'Config generations', `${snapshot.generations.length} landscape compilers`)}
  ${
    snapshot.generations.length === 0
      ? empty('No configuration generation telemetry is available.')
      : `<div class="table-wrap"><table>
        <caption>Generation-swapped derived configuration. Long-lived account and tenant truth remains on the management plane.</caption>
        <thead><tr><th>Landscape</th><th>Status</th><th class="numeric">Desired</th><th class="numeric">Active</th><th>Compiled</th><th>Detail</th></tr></thead>
        <tbody>${snapshot.generations
          .map(
            item => `<tr>
              <td>${escapeHtml(item.landscape)}</td>
              <td>${stateChip(item.state)}</td>
              <td class="numeric">${formatNumber(item.desiredGeneration)}</td>
              <td class="numeric">${formatNumber(item.activeGeneration)}</td>
              <td>${timestamp(item.compiledAt)}</td>
              <td>${escapeHtml(item.detail ?? 'Nominal')}</td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

const archiveSection = (snapshot: ConsoleDashboardSnapshot): string => `
<section class="section" id="archive" aria-labelledby="archive-title">
  ${sectionHeading('archive', 'Archive interlock', `${snapshot.archives.length} landscape archives`)}
  ${
    snapshot.archives.length === 0
      ? empty('No archive telemetry is available.')
      : `<div class="telemetry-strip">${snapshot.archives
          .map(
            item => `<article class="telemetry-cell">
              <div class="telemetry-cell__top"><h3 class="telemetry-cell__name">${escapeHtml(
                item.landscape,
              )}</h3>${stateChip(item.state)}</div>
              <dl>
                <dt>Pending streams</dt><dd>${formatNumber(item.pendingStreams)}</dd>
                <dt>Pending bytes</dt><dd>${bytes(item.pendingBytes)}</dd>
                <dt>Last archived</dt><dd>${timestamp(item.lastArchivedAt)}</dd>
                <dt>Deletion</dt><dd>${item.deletionBlocked ? stateChip('blocked') : stateChip('healthy')}</dd>
              </dl>
              ${item.detail === undefined ? '' : `<p class="form-help">${escapeHtml(item.detail)}</p>`}
            </article>`,
          )
          .join('')}</div>`
  }
</section>`;

const quotaSection = (snapshot: ConsoleDashboardSnapshot): string => `
<section class="section" id="quota" aria-labelledby="quota-title">
  ${sectionHeading('quota', 'Quota state', `${snapshot.quotas.length} tenant windows`)}
  ${
    snapshot.quotas.length === 0
      ? empty('No quota windows match this fan-in matrix.')
      : `<div class="table-wrap"><table>
        <caption>In-app tenant quota enforcement covers public and private paths.</caption>
        <thead><tr><th>Tenant</th><th>Status</th><th>Window</th><th class="numeric">Used</th><th class="numeric">Limit</th><th class="numeric">Utilization</th><th>Resets</th></tr></thead>
        <tbody>${snapshot.quotas
          .map(
            item => `<tr>
              <td>${escapeHtml(item.tenant)}</td>
              <td>${stateChip(item.state)}</td>
              <td>${escapeHtml(item.window)}</td>
              <td class="numeric">${formatNumber(item.used)}</td>
              <td class="numeric">${formatNumber(item.limit)}</td>
              <td class="numeric">${percentage(item.limit === 0 ? 1 : item.used / item.limit)}</td>
              <td>${timestamp(item.resetsAt)}</td>
            </tr>`,
          )
          .join('')}</tbody>
      </table></div>`
  }
</section>`;

export interface DashboardViewInput {
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly snapshot: ConsoleDashboardSnapshot;
  readonly filters: ConsoleFilters;
  readonly capabilities: readonly ConsoleCapability[];
}

export const renderDashboard = (input: DashboardViewInput): string =>
  shell({
    title: 'Operations fan-in',
    eyebrow: 'Mercury / retained flow / account scope',
    nonce: input.nonce,
    identity: input.identity,
    csrfToken: input.csrfToken,
    generatedAt: input.snapshot.generatedAt,
    body: `
      <div class="notice" data-preview-visibility="${escapeHtml(input.snapshot.previewVisibility.state)}">
        <strong class="notice__code">${
          input.snapshot.previewVisibility.state === 'withheld-d11' ? 'D11' : 'VIS'
        }</strong>
        <p><strong>Preview callback delivery visibility: ${
          input.snapshot.previewVisibility.state === 'withheld-d11' ? 'WITHHELD' : 'AVAILABLE'
        }</strong><br>${escapeHtml(input.snapshot.previewVisibility.detail)}${
          input.snapshot.previewVisibility.affectedLandscapes.length === 0
            ? ''
            : ` Affected: ${escapeHtml(input.snapshot.previewVisibility.affectedLandscapes.join(', '))}.`
        } Intake, route registry state, retained-event inspection, replay, configuration, archive, and quota controls remain available.</p>
      </div>
      ${sourceFailureNotice(input.snapshot)}
      ${filterMatrix(input.snapshot, input.filters)}
      ${intakeSection(input.snapshot)}
      ${deliverySection(input.snapshot, input.capabilities)}
      ${eventSection(input.snapshot, input.capabilities)}
      ${deadLetterSection(input.snapshot, input.capabilities)}
      ${routeSection(input.snapshot)}
      ${configurationSection(input.snapshot)}
      ${archiveSection(input.snapshot)}
      ${quotaSection(input.snapshot)}
    `,
  });

const detailRows = (event: ConsoleEventDetail): string => `
<dl class="definition">
  <div><dt>Event ID</dt><dd>${escapeHtml(event.id)}</dd></div>
  <div><dt>Landing landscape</dt><dd>${escapeHtml(event.landscape)}</dd></div>
  <div><dt>Tenant</dt><dd>${escapeHtml(event.tenant)}</dd></div>
  <div><dt>Provider / route</dt><dd>${escapeHtml(event.provider)} / ${escapeHtml(event.route)}</dd></div>
  <div><dt>Endpoint</dt><dd>${escapeHtml(event.endpointName)} · ${escapeHtml(event.endpointId)}</dd></div>
  <div><dt>Delivery address</dt><dd>${escapeHtml(event.deliveryAddress)}</dd></div>
  <div><dt>Status</dt><dd>${stateChip(event.status)}</dd></div>
  <div><dt>Received</dt><dd>${timestamp(event.receivedAt)}</dd></div>
  <div><dt>Provider time</dt><dd>${timestamp(event.providerTimestamp)}</dd></div>
  <div><dt>Provider sequence</dt><dd>${escapeHtml(event.providerSequence ?? 'NOT PROVIDED')}</dd></div>
  <div><dt>Attempts / lag</dt><dd>${formatNumber(event.attemptCount)} / ${duration(event.lagSeconds)}</dd></div>
  <div><dt>Last response</dt><dd>${escapeHtml(
    event.lastResponseStatus === undefined ? 'NO RESPONSE' : String(event.lastResponseStatus),
  )}</dd></div>
</dl>`;

const recordRows = (values: Readonly<Record<string, string>>): string =>
  Object.entries(values).length === 0
    ? empty('No retained values in this metadata set.')
    : `<dl class="definition">${Object.entries(values)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, value]) => `<div><dt>${escapeHtml(key)}</dt><dd>${escapeHtml(value)}</dd></div>`)
        .join('')}</dl>`;

export interface EventViewInput {
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly event: ConsoleEventDetail;
  readonly canReplay: boolean;
}

export const renderEvent = (input: EventViewInput): string =>
  shell({
    title: 'Retained event detail',
    eyebrow: `${input.event.landscape} / ${input.event.provider}`,
    nonce: input.nonce,
    identity: input.identity,
    csrfToken: input.csrfToken,
    generatedAt: input.event.receivedAt,
    body: `
      <p><a href="/console#events">← Return to fan-in ledger</a></p>
      ${
        input.canReplay
          ? `<div class="actions"><a class="button button--danger" href="/console/events/${pathSegment(
              input.event.landscape,
            )}/${pathSegment(input.event.id)}/replay">Replay this event</a></div>`
          : '<p class="muted">This account has read-only access to retained events.</p>'
      }
      <section class="section" aria-labelledby="identity-title">
        ${sectionHeading('identity', 'Identity and delivery', 'Name-blind retained envelope')}
        <div class="split">
          ${detailRows(input.event)}
          <div><h3>Metadata</h3>${recordRows(input.event.metadata)}</div>
        </div>
      </section>
      <section class="section" aria-labelledby="headers-title">
        ${sectionHeading(
          'headers',
          'Allowed headers',
          `${Object.keys(input.event.allowedHeaders).length} retained entries`,
        )}
        ${recordRows(input.event.allowedHeaders)}
      </section>
      <section class="section" aria-labelledby="payload-title">
        ${sectionHeading('payload', 'Raw payload', input.event.payloadMediaType)}
        <pre class="code-block"><code>${escapeHtml(input.event.payload)}</code></pre>
      </section>
      ${
        input.event.lastResponseBody === undefined
          ? ''
          : `<section class="section" aria-labelledby="response-title">
              ${sectionHeading(
                'response',
                'Last endpoint response',
                String(input.event.lastResponseStatus ?? 'network error'),
              )}
              <pre class="code-block"><code>${escapeHtml(input.event.lastResponseBody)}</code></pre>
            </section>`
      }
    `,
  });

export type ConfirmationKind = 'replay-event' | 'replay-endpoint' | 'reenable-endpoint';

export interface ConfirmationViewInput {
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly kind: ConfirmationKind;
  readonly event?: ConsoleEventDetail;
  readonly endpoint?: ConsoleEndpointReplayTarget;
  readonly selectedEndpointId?: string;
}

interface ConfirmationShape {
  readonly title: string;
  readonly phrase: string;
  readonly action: string;
  readonly description: string;
  readonly target: string;
}

const confirmationShape = (input: ConfirmationViewInput): ConfirmationShape => {
  if (input.kind === 'replay-event' && input.event !== undefined) {
    const endpointQuery =
      input.selectedEndpointId === undefined ? '' : `?endpoint=${encodeURIComponent(input.selectedEndpointId)}`;
    return {
      title: input.selectedEndpointId === undefined ? 'Replay retained event' : 'Replay delivery obligation',
      phrase: 'REPLAY EVENT',
      action: `/console/events/${pathSegment(input.event.landscape)}/${pathSegment(
        input.event.id,
      )}/replay${endpointQuery}`,
      description:
        'Mercury will re-enqueue the retained event in its landing landscape. Every new attempt receives a fresh internal signature.',
      target: `${input.event.id} · ${input.event.landscape} · ${input.selectedEndpointId ?? 'all event obligations'}`,
    };
  }

  if (input.kind === 'replay-endpoint' && input.endpoint !== undefined) {
    return {
      title: 'Replay endpoint dead letters',
      phrase: 'REPLAY ENDPOINT',
      action: `/console/endpoints/${pathSegment(input.endpoint.landscape)}/${pathSegment(
        input.endpoint.endpointId,
      )}/replay`,
      description: `Mercury will enqueue ${
        input.endpoint.replayableEvents
      } replayable retained obligation(s) for this endpoint in their owning landscapes.`,
      target: `${input.endpoint.endpointName} · ${input.endpoint.tenant} · ${input.endpoint.endpointId}`,
    };
  }

  if (input.kind === 'reenable-endpoint' && input.endpoint !== undefined) {
    return {
      title: 'Re-enable delivery circuit',
      phrase: 'REENABLE',
      action: `/console/endpoints/${pathSegment(input.endpoint.landscape)}/${pathSegment(
        input.endpoint.endpointId,
      )}/reenable`,
      description:
        'Mercury will close the manual circuit interlock and allow active retries to resume. Existing delivery obligations are not discarded.',
      target: `${input.endpoint.endpointName} · ${input.endpoint.landscape} · circuit ${input.endpoint.circuit}`,
    };
  }

  throw new Error('Confirmation view target does not match its action kind');
};

export const renderConfirmation = (input: ConfirmationViewInput): string => {
  const shape = confirmationShape(input);
  return shell({
    title: shape.title,
    eyebrow: 'Explicit operator confirmation',
    nonce: input.nonce,
    identity: input.identity,
    csrfToken: input.csrfToken,
    body: `<section class="confirm" aria-labelledby="confirm-title">
      <p class="eyebrow">State-changing native API request</p>
      <h2 id="confirm-title">${escapeHtml(shape.title)}</h2>
      <p>${escapeHtml(shape.description)}</p>
      <p class="confirm__target"><strong>Target</strong><br>${escapeHtml(shape.target)}</p>
      <form method="post" action="${escapeHtml(shape.action)}" data-confirm-form>
        <input type="hidden" name="csrf" value="${escapeHtml(input.csrfToken)}">
        <div class="confirm__grid">
          <div>
            <label for="confirmation">Type ${escapeHtml(shape.phrase)}</label>
            <input id="confirmation" name="confirmation" type="text" required pattern="${escapeHtml(
              shape.phrase,
            )}" maxlength="32" autocomplete="off" data-confirm-input data-expected="${escapeHtml(
              shape.phrase,
            )}" aria-describedby="confirm-status">
            <p class="form-help" id="confirm-status" data-confirm-status aria-live="polite">Exact phrase required.</p>
          </div>
          <div>
            <label for="reason">Audit reason</label>
            <textarea id="reason" name="reason" minlength="3" maxlength="240" required placeholder="Why is this operation necessary?"></textarea>
          </div>
        </div>
        <div class="confirm__actions">
          <button class="button--danger" type="submit">Execute control</button>
          <a class="button button--ghost" href="/console">Cancel</a>
        </div>
      </form>
    </section>`,
  });
};

export interface OutcomeViewInput {
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly receipt?: ConsoleActionReceipt;
  readonly failure?: ConsoleFailure;
}

export const renderOutcome = (input: OutcomeViewInput): string => {
  const succeeded = input.receipt !== undefined;
  const title = succeeded ? input.receipt.title : (input.failure?.title ?? 'Control request failed');
  const detail = succeeded ? input.receipt.detail : (input.failure?.detail ?? 'No detail was returned.');

  return shell({
    title,
    eyebrow: succeeded ? 'Control request accepted' : 'Control request rejected',
    nonce: input.nonce,
    identity: input.identity,
    csrfToken: input.csrfToken,
    generatedAt: input.receipt?.acceptedAt,
    body: `<section class="confirm" aria-labelledby="result-title">
      <span class="result-mark${succeeded ? '' : ' result-mark--bad'}" aria-hidden="true">${
        succeeded ? '✓' : '!'
      }</span>
      <p class="eyebrow">${succeeded ? 'Accepted by scoped operations service' : 'No operation was applied'}</p>
      <h2 id="result-title">${escapeHtml(title)}</h2>
      <p role="${succeeded ? 'status' : 'alert'}">${escapeHtml(detail)}</p>
      ${
        input.receipt === undefined
          ? ''
          : `<dl class="definition">
              <div><dt>Action ID</dt><dd>${escapeHtml(input.receipt.actionId)}</dd></div>
              <div><dt>Landscape</dt><dd>${escapeHtml(input.receipt.landscape)}</dd></div>
              <div><dt>Affected obligations</dt><dd>${formatNumber(input.receipt.affectedCount)}</dd></div>
              <div><dt>Accepted</dt><dd>${timestamp(input.receipt.acceptedAt)}</dd></div>
            </dl>`
      }
      <p><a class="button" href="/console">Return to operations</a></p>
    </section>`,
  });
};

export interface FailureViewInput {
  readonly nonce: string;
  readonly identity: ConsoleIdentity;
  readonly csrfToken: string;
  readonly failure: ConsoleFailure;
}

export const renderFailure = (input: FailureViewInput): string =>
  shell({
    title: input.failure.title,
    eyebrow: 'Operations boundary response',
    nonce: input.nonce,
    identity: input.identity,
    csrfToken: input.csrfToken,
    body: `<div class="notice notice--bad" role="alert">
      <strong class="notice__code">${escapeHtml(input.failure.kind.toUpperCase())}</strong>
      <p>${escapeHtml(input.failure.detail)}</p>
    </div>
    <p><a class="button button--ghost" href="/console">Return to operations</a></p>`,
  });
