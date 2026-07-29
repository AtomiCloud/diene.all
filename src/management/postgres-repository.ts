import type postgres from 'postgres';
import { ManagementError } from './errors.ts';
import type {
  EndpointSigningCredentialRotation,
  ManagementRepository,
  ProviderCredentialRotation,
} from './repository.ts';
import type {
  Account,
  ConfigGeneration,
  CustomDomain,
  Endpoint,
  EndpointSigningCredential,
  EndpointTarget,
  LandscapeAcknowledgement,
  LandscapeEventSource,
  MeteringConfiguration,
  NativeCredential,
  ProviderCredential,
  Quota,
  ReplayAudit,
  ReplayScope,
  Route,
  SubscriptionRegistration,
  Tenant,
  TenantConfiguration,
} from './types.ts';

type Sql = postgres.Sql;
type DbRow = Record<string, unknown>;

function date(value: unknown): Date {
  return value instanceof Date ? value : new Date(String(value));
}

function optionalDate(value: unknown): Date | undefined {
  return value === null || value === undefined ? undefined : date(value);
}

function stringValue(value: unknown): string {
  return String(value);
}

function optionalString(value: unknown): string | undefined {
  return value === null || value === undefined ? undefined : String(value);
}

function numberValue(value: unknown): number {
  return Number(value);
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.map(String) : [];
}

function jsonRecord(value: unknown): Readonly<Record<string, unknown>> {
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  if (typeof value === 'string') {
    return JSON.parse(value) as Record<string, unknown>;
  }
  return {};
}

function accountFrom(row: DbRow): Account {
  return {
    id: stringValue(row.id),
    name: stringValue(row.name),
    kind: row.kind as Account['kind'],
    status: row.status as Account['status'],
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function tenantFrom(row: DbRow): Tenant {
  return {
    id: stringValue(row.id),
    accountId: stringValue(row.account_id),
    name: stringValue(row.name),
    intakeSlug: stringValue(row.intake_slug),
    source: row.source as Tenant['source'],
    homeVlandscape: stringValue(row.home_vlandscape),
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function quotaFrom(row: DbRow): Quota {
  return {
    tenantId: stringValue(row.tenant_id),
    intakeRps: numberValue(row.intake_rps),
    burst: numberValue(row.burst),
    managementRps: numberValue(row.management_rps),
    retryWindowSeconds: numberValue(row.retry_window_seconds),
    dedupWindowSeconds: numberValue(row.dedup_window_seconds),
    retentionMonths: numberValue(row.retention_months),
    updatedAt: date(row.updated_at),
  };
}

function meteringFrom(row: DbRow): MeteringConfiguration {
  return {
    tenantId: stringValue(row.tenant_id),
    enabled: Boolean(row.enabled),
    exportIntervalSeconds: numberValue(row.export_interval_seconds),
    dimensions: stringArray(row.dimensions),
    billingAccountReference: optionalString(row.billing_account_reference),
    updatedAt: date(row.updated_at),
  };
}

function credentialFrom(row: DbRow): NativeCredential {
  return {
    id: stringValue(row.id),
    accountId: stringValue(row.account_id),
    tenantId: optionalString(row.tenant_id),
    kind: row.kind as NativeCredential['kind'],
    generation: numberValue(row.generation),
    tokenHash: optionalString(row.token_hash),
    secretPointer: optionalString(row.secret_pointer),
    scopes: stringArray(row.scopes),
    status: row.status as NativeCredential['status'],
    liveFrom: optionalDate(row.live_from),
    lastConfirmedAt: optionalDate(row.last_confirmed_at),
    overlapUntil: optionalDate(row.overlap_until),
    revokedAt: optionalDate(row.revoked_at),
    createdAt: date(row.created_at),
  };
}

function providerCredentialFrom(row: DbRow): ProviderCredential {
  return {
    id: stringValue(row.id),
    accountId: stringValue(row.account_id),
    tenantId: stringValue(row.tenant_id),
    provider: stringValue(row.provider),
    generation: numberValue(row.generation),
    secretPointer: stringValue(row.secret_pointer),
    status: row.status as ProviderCredential['status'],
    lastConfirmedAt: optionalDate(row.last_confirmed_at),
    overlapUntil: optionalDate(row.overlap_until),
    createdAt: date(row.created_at),
  };
}

function endpointSigningCredentialFrom(row: DbRow): EndpointSigningCredential {
  return {
    id: stringValue(row.id),
    accountId: stringValue(row.account_id),
    tenantId: stringValue(row.tenant_id),
    endpointId: stringValue(row.endpoint_id),
    generation: numberValue(row.generation),
    secretPointer: stringValue(row.secret_pointer),
    status: row.status as EndpointSigningCredential['status'],
    lastConfirmedAt: optionalDate(row.last_confirmed_at),
    overlapUntil: optionalDate(row.overlap_until),
    createdAt: date(row.created_at),
  };
}

function domainFrom(row: DbRow): CustomDomain {
  return {
    id: stringValue(row.id),
    tenantId: stringValue(row.tenant_id),
    hostname: stringValue(row.hostname),
    registeredUrl: stringValue(row.registered_url),
    intakeTarget: stringValue(row.intake_target),
    challengeTarget: stringValue(row.challenge_target),
    certificateSecretPointer: stringValue(row.certificate_secret_pointer),
    status: row.status as CustomDomain['status'],
    verificationTokenHash: stringValue(row.verification_token_hash),
    pendingUntil: date(row.pending_until),
    verifiedAt: optionalDate(row.verified_at),
    activatedAt: optionalDate(row.activated_at),
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function routeFrom(row: DbRow): Route {
  return {
    id: stringValue(row.id),
    tenantId: stringValue(row.tenant_id),
    path: stringValue(row.path),
    registeredUrl: stringValue(row.registered_url),
    provider: stringValue(row.provider),
    scheme: optionalString(row.scheme),
    providerCredentialId: optionalString(row.provider_credential_id),
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function endpointTargetFrom(row: DbRow): EndpointTarget {
  if (row.target_kind === 'url') {
    return { kind: 'url', url: stringValue(row.target_url) };
  }
  return {
    kind: 'coordinate',
    service: stringValue(row.target_service),
    module: stringValue(row.target_module),
    canonicalVlandscape: stringValue(row.canonical_vlandscape),
  };
}

function endpointFrom(row: DbRow): Endpoint {
  return {
    id: stringValue(row.id),
    routeId: stringValue(row.route_id),
    target: endpointTargetFrom(row),
    signingCredentialId: stringValue(row.signing_credential_id),
    circuitState: row.circuit_state as Endpoint['circuitState'],
    circuitOpenedAt: optionalDate(row.circuit_opened_at),
    lastProbeAt: optionalDate(row.last_probe_at),
    lastProbeSucceededAt: optionalDate(row.last_probe_succeeded_at),
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function subscriptionFrom(row: DbRow): SubscriptionRegistration {
  return {
    id: stringValue(row.id),
    tenantId: stringValue(row.tenant_id),
    provider: stringValue(row.provider),
    externalId: stringValue(row.external_id),
    retentionSeconds: row.retention_seconds === null ? undefined : numberValue(row.retention_seconds),
    deadLetterTarget: optionalString(row.dead_letter_target),
    metadata: jsonRecord(row.metadata),
    createdAt: date(row.created_at),
    updatedAt: date(row.updated_at),
  };
}

function sourceFrom(row: DbRow): LandscapeEventSource {
  return {
    accountId: stringValue(row.account_id),
    landscape: stringValue(row.landscape),
    queryUrl: stringValue(row.query_url),
    replayUrl: stringValue(row.replay_url),
    credentialPointer: stringValue(row.credential_pointer),
    enabled: Boolean(row.enabled),
    updatedAt: date(row.updated_at),
  };
}

function replayScopeFrom(row: DbRow): ReplayScope {
  return row.scope_kind === 'event'
    ? { kind: 'event', eventId: stringValue(row.event_id) }
    : { kind: 'endpoint', endpointId: stringValue(row.endpoint_id) };
}

function replayFrom(row: DbRow): ReplayAudit {
  return {
    id: stringValue(row.id),
    accountId: stringValue(row.account_id),
    tenantId: stringValue(row.tenant_id),
    landscape: stringValue(row.landscape),
    scope: replayScopeFrom(row),
    reason: stringValue(row.reason),
    commandId: stringValue(row.command_id),
    requestedAt: date(row.requested_at),
  };
}

function generationFrom(row: DbRow): ConfigGeneration {
  return {
    generation: numberValue(row.generation),
    landscape: stringValue(row.landscape),
    status: row.status as ConfigGeneration['status'],
    contentHash: stringValue(row.content_hash),
    previousGeneration: row.previous_generation === null ? undefined : numberValue(row.previous_generation),
    graceUntil: optionalDate(row.grace_until),
    createdAt: date(row.created_at),
    activatedAt: optionalDate(row.activated_at),
  };
}

function acknowledgementFrom(row: DbRow): LandscapeAcknowledgement {
  return {
    landscape: stringValue(row.landscape),
    generation: numberValue(row.generation),
    acknowledgedAt: date(row.acknowledged_at),
    contentHash: stringValue(row.content_hash),
  };
}

function first<T>(rows: readonly DbRow[], convert: (row: DbRow) => T): T | undefined {
  const row = rows[0];
  return row === undefined ? undefined : convert(row);
}

export class PostgresManagementRepository implements ManagementRepository {
  public constructor(private readonly sql: Sql) {}

  public async health(): Promise<boolean> {
    try {
      await this.sql`SELECT 1`;
      return true;
    } catch {
      return false;
    }
  }

  public async getAccount(id: string): Promise<Account | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.accounts WHERE id = ${id}
    `;
    return first(rows, accountFrom);
  }

  public async findAccountByName(name: string): Promise<Account | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.accounts WHERE name = ${name}
    `;
    return first(rows, accountFrom);
  }

  public async listAccounts(): Promise<readonly Account[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.accounts ORDER BY name
    `;
    return rows.map(accountFrom);
  }

  public async saveAccount(account: Account): Promise<Account> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.accounts
        (id, name, kind, status, created_at, updated_at)
      VALUES
        (${account.id}, ${account.name}, ${account.kind}, ${account.status},
         ${account.createdAt}, ${account.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        status = EXCLUDED.status,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return accountFrom(rows[0] as DbRow);
  }

  public async getTenant(id: string): Promise<Tenant | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.tenants WHERE id = ${id}
    `;
    return first(rows, tenantFrom);
  }

  public async findTenantByName(name: string): Promise<Tenant | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.tenants WHERE name = ${name}
    `;
    return first(rows, tenantFrom);
  }

  public async findTenantByIntakeSlug(slug: string): Promise<Tenant | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.tenants WHERE intake_slug = ${slug}
    `;
    return first(rows, tenantFrom);
  }

  public async listTenants(accountId?: string): Promise<readonly Tenant[]> {
    const rows =
      accountId === undefined
        ? await this.sql<DbRow[]>`
            SELECT * FROM mercury_management.tenants ORDER BY name
          `
        : await this.sql<DbRow[]>`
            SELECT * FROM mercury_management.tenants
            WHERE account_id = ${accountId}
            ORDER BY name
          `;
    return rows.map(tenantFrom);
  }

  public async saveTenant(tenant: Tenant): Promise<Tenant> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.tenants
        (id, account_id, name, intake_slug, source, home_vlandscape,
         created_at, updated_at)
      VALUES
        (${tenant.id}, ${tenant.accountId}, ${tenant.name},
         ${tenant.intakeSlug}, ${tenant.source}, ${tenant.homeVlandscape},
         ${tenant.createdAt}, ${tenant.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        account_id = EXCLUDED.account_id,
        name = EXCLUDED.name,
        source = EXCLUDED.source,
        updated_at = EXCLUDED.updated_at
      WHERE mercury_management.tenants.home_vlandscape =
        EXCLUDED.home_vlandscape
        AND mercury_management.tenants.intake_slug = EXCLUDED.intake_slug
      RETURNING *
    `;
    if (rows[0] === undefined) {
      throw new ManagementError('immutable_home', 'tenant home_vlandscape and intake_slug are immutable');
    }
    return tenantFrom(rows[0] as DbRow);
  }

  public async deleteTenant(id: string): Promise<boolean> {
    const rows = await this.sql<DbRow[]>`
      DELETE FROM mercury_management.tenants tenant
      WHERE tenant.id = ${id}
        AND NOT EXISTS (SELECT 1 FROM mercury_management.native_credentials item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.provider_credentials item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.endpoint_signing_credentials item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.custom_domains item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.routes item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.subscription_registrations item WHERE item.tenant_id = tenant.id)
        AND NOT EXISTS (SELECT 1 FROM mercury_management.replay_audit item WHERE item.tenant_id = tenant.id)
      RETURNING id
    `;
    return rows.length === 1;
  }

  public async getQuota(tenantId: string): Promise<Quota | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.quotas WHERE tenant_id = ${tenantId}
    `;
    return first(rows, quotaFrom);
  }

  public async saveQuota(quota: Quota): Promise<Quota> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.quotas
        (tenant_id, intake_rps, burst, management_rps,
         retry_window_seconds, dedup_window_seconds, retention_months,
         updated_at)
      VALUES
        (${quota.tenantId}, ${quota.intakeRps}, ${quota.burst},
         ${quota.managementRps}, ${quota.retryWindowSeconds},
         ${quota.dedupWindowSeconds}, ${quota.retentionMonths},
         ${quota.updatedAt})
      ON CONFLICT (tenant_id) DO UPDATE SET
        intake_rps = EXCLUDED.intake_rps,
        burst = EXCLUDED.burst,
        management_rps = EXCLUDED.management_rps,
        retry_window_seconds = EXCLUDED.retry_window_seconds,
        dedup_window_seconds = EXCLUDED.dedup_window_seconds,
        retention_months = EXCLUDED.retention_months,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return quotaFrom(rows[0] as DbRow);
  }

  public async getMeteringConfiguration(tenantId: string): Promise<MeteringConfiguration | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.metering_configuration
      WHERE tenant_id = ${tenantId}
    `;
    return first(rows, meteringFrom);
  }

  public async saveMeteringConfiguration(configuration: MeteringConfiguration): Promise<MeteringConfiguration> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.metering_configuration
        (tenant_id, enabled, export_interval_seconds, dimensions,
         billing_account_reference, updated_at)
      VALUES
        (${configuration.tenantId}, ${configuration.enabled},
         ${configuration.exportIntervalSeconds},
         ${this.sql.array([...configuration.dimensions])},
         ${configuration.billingAccountReference ?? null},
         ${configuration.updatedAt})
      ON CONFLICT (tenant_id) DO UPDATE SET
        enabled = EXCLUDED.enabled,
        export_interval_seconds = EXCLUDED.export_interval_seconds,
        dimensions = EXCLUDED.dimensions,
        billing_account_reference = EXCLUDED.billing_account_reference,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return meteringFrom(rows[0] as DbRow);
  }

  public async getCredential(id: string): Promise<NativeCredential | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.native_credentials WHERE id = ${id}
    `;
    return first(rows, credentialFrom);
  }

  public async findCredentialByTokenHash(tokenHash: string): Promise<NativeCredential | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.native_credentials
      WHERE token_hash = ${tokenHash}
    `;
    return first(rows, credentialFrom);
  }

  public async listCredentials(accountId: string): Promise<readonly NativeCredential[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.native_credentials
      WHERE account_id = ${accountId}
      ORDER BY kind, generation
    `;
    return rows.map(credentialFrom);
  }

  public async saveCredential(credential: NativeCredential): Promise<NativeCredential> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.native_credentials
        (id, account_id, tenant_id, kind, generation, token_hash,
         secret_pointer, scopes, status, live_from, last_confirmed_at,
         overlap_until, revoked_at, created_at)
      VALUES
        (${credential.id}, ${credential.accountId},
         ${credential.tenantId ?? null}, ${credential.kind},
         ${credential.generation}, ${credential.tokenHash ?? null},
         ${credential.secretPointer ?? null},
         ${this.sql.array([...credential.scopes])}, ${credential.status},
         ${credential.liveFrom ?? null}, ${credential.lastConfirmedAt ?? null},
         ${credential.overlapUntil ?? null}, ${credential.revokedAt ?? null},
         ${credential.createdAt})
      ON CONFLICT (id) DO UPDATE SET
        token_hash = EXCLUDED.token_hash,
        secret_pointer = EXCLUDED.secret_pointer,
        scopes = EXCLUDED.scopes,
        status = EXCLUDED.status,
        live_from = EXCLUDED.live_from,
        last_confirmed_at = EXCLUDED.last_confirmed_at,
        overlap_until = EXCLUDED.overlap_until,
        revoked_at = EXCLUDED.revoked_at
      RETURNING *
    `;
    return credentialFrom(rows[0] as DbRow);
  }

  public async consumeManagementRate(
    credentialId: string,
    windowSecond: number,
    cost: number,
    limit: number,
  ): Promise<boolean> {
    const rows = await this.sql<DbRow[]>`
      WITH pruned AS (
        DELETE FROM mercury_management.management_rate_windows
        WHERE credential_id = ${credentialId}
          AND window_second < ${windowSecond - 60}
      )
      INSERT INTO mercury_management.management_rate_windows
        (credential_id, window_second, cost)
      VALUES (${credentialId}, ${windowSecond}, ${cost})
      ON CONFLICT (credential_id, window_second) DO UPDATE SET
        cost = mercury_management.management_rate_windows.cost + EXCLUDED.cost
      WHERE mercury_management.management_rate_windows.cost + EXCLUDED.cost <= ${limit}
      RETURNING cost
    `;
    return rows.length === 1;
  }

  public async listProviderCredentials(tenantId: string): Promise<readonly ProviderCredential[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.provider_credentials
      WHERE tenant_id = ${tenantId}
      ORDER BY provider, generation
    `;
    return rows.map(providerCredentialFrom);
  }

  public async getProviderCredential(id: string): Promise<ProviderCredential | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.provider_credentials WHERE id = ${id}
    `;
    return first(rows, providerCredentialFrom);
  }

  public async saveProviderCredential(credential: ProviderCredential): Promise<ProviderCredential> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.provider_credentials
        (id, account_id, tenant_id, provider, generation, secret_pointer, status,
         last_confirmed_at, overlap_until, created_at)
      VALUES
        (${credential.id}, ${credential.accountId}, ${credential.tenantId}, ${credential.provider},
         ${credential.generation}, ${credential.secretPointer},
         ${credential.status}, ${credential.lastConfirmedAt ?? null},
         ${credential.overlapUntil ?? null}, ${credential.createdAt})
      ON CONFLICT (id) DO UPDATE SET
        secret_pointer = EXCLUDED.secret_pointer,
        status = EXCLUDED.status,
        last_confirmed_at = EXCLUDED.last_confirmed_at,
        overlap_until = EXCLUDED.overlap_until
      RETURNING *
    `;
    return providerCredentialFrom(rows[0] as DbRow);
  }

  public async rotateProviderCredential(rotation: ProviderCredentialRotation): Promise<ProviderCredential> {
    const rows = await this.sql.begin(async transaction => {
      await transaction`
        SELECT pg_advisory_xact_lock(
          hashtextextended(${`mercury:provider-credential:${rotation.tenantId}:${rotation.provider}`}, 0)
        )
      `;
      const generationRows = await transaction<DbRow[]>`
        SELECT COALESCE(MAX(generation), 0) + 1 AS generation
        FROM mercury_management.provider_credentials
        WHERE tenant_id = ${rotation.tenantId}
          AND provider = ${rotation.provider}
      `;
      const generation = numberValue((generationRows[0] as DbRow).generation);
      await transaction`
        UPDATE mercury_management.provider_credentials
        SET status = 'overlap',
            last_confirmed_at = ${rotation.rotatedAt},
            overlap_until = ${rotation.overlapUntil}
        WHERE tenant_id = ${rotation.tenantId}
          AND provider = ${rotation.provider}
          AND status = 'live'
      `;
      return transaction<DbRow[]>`
        INSERT INTO mercury_management.provider_credentials
          (id, account_id, tenant_id, provider, generation, secret_pointer,
           status, last_confirmed_at, overlap_until, created_at)
        VALUES
          (${rotation.id}, ${rotation.accountId}, ${rotation.tenantId},
           ${rotation.provider}, ${generation}, ${rotation.secretPointer},
           'live', ${rotation.rotatedAt}, NULL, ${rotation.rotatedAt})
        RETURNING *
      `;
    });
    return providerCredentialFrom(rows[0] as DbRow);
  }

  public async getEndpointSigningCredential(id: string): Promise<EndpointSigningCredential | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.endpoint_signing_credentials WHERE id = ${id}
    `;
    return first(rows, endpointSigningCredentialFrom);
  }

  public async listEndpointSigningCredentials(tenantId: string): Promise<readonly EndpointSigningCredential[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.endpoint_signing_credentials
      WHERE tenant_id = ${tenantId}
      ORDER BY endpoint_id, generation
    `;
    return rows.map(endpointSigningCredentialFrom);
  }

  public async saveEndpointSigningCredential(
    credential: EndpointSigningCredential,
  ): Promise<EndpointSigningCredential> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.endpoint_signing_credentials
        (id, account_id, tenant_id, endpoint_id, generation, secret_pointer,
         status, last_confirmed_at, overlap_until, created_at)
      VALUES
        (${credential.id}, ${credential.accountId}, ${credential.tenantId},
         ${credential.endpointId}, ${credential.generation}, ${credential.secretPointer},
         ${credential.status}, ${credential.lastConfirmedAt ?? null},
         ${credential.overlapUntil ?? null}, ${credential.createdAt})
      ON CONFLICT (id) DO UPDATE SET
        secret_pointer = EXCLUDED.secret_pointer,
        status = EXCLUDED.status,
        last_confirmed_at = EXCLUDED.last_confirmed_at,
        overlap_until = EXCLUDED.overlap_until
      RETURNING *
    `;
    return endpointSigningCredentialFrom(rows[0] as DbRow);
  }

  public async rotateEndpointSigningCredential(
    rotation: EndpointSigningCredentialRotation,
  ): Promise<EndpointSigningCredential> {
    const rows = await this.sql.begin(async transaction => {
      await transaction`
        SELECT pg_advisory_xact_lock(
          hashtextextended(${`mercury:endpoint-signing:${rotation.tenantId}:${rotation.endpointId}`}, 0)
        )
      `;
      const endpointRows = await transaction<DbRow[]>`
        SELECT endpoint_record.signing_credential_id,
               route_record.tenant_id AS endpoint_tenant_id,
               credential.account_id AS credential_account_id,
               credential.tenant_id AS credential_tenant_id,
               credential.endpoint_id AS credential_endpoint_id,
               credential.status AS credential_status
        FROM mercury_management.endpoints endpoint_record
        JOIN mercury_management.routes route_record
          ON route_record.id = endpoint_record.route_id
        LEFT JOIN mercury_management.endpoint_signing_credentials credential
          ON credential.id = endpoint_record.signing_credential_id
        WHERE endpoint_record.id = ${rotation.endpointId}
        FOR UPDATE OF endpoint_record
      `;
      const endpointRow = endpointRows[0];
      if (
        (endpointRow === undefined && rotation.expectedCurrentCredentialId !== undefined) ||
        (endpointRow !== undefined && rotation.expectedCurrentCredentialId === undefined) ||
        (endpointRow !== undefined &&
          (stringValue(endpointRow.signing_credential_id) !== rotation.expectedCurrentCredentialId ||
            stringValue(endpointRow.endpoint_tenant_id) !== rotation.tenantId ||
            stringValue(endpointRow.credential_account_id) !== rotation.accountId ||
            stringValue(endpointRow.credential_tenant_id) !== rotation.tenantId ||
            stringValue(endpointRow.credential_endpoint_id) !== rotation.endpointId ||
            stringValue(endpointRow.credential_status) !== 'live'))
      ) {
        throw new ManagementError('conflict', 'endpoint signing credential changed during rotation');
      }
      const generationRows = await transaction<DbRow[]>`
        SELECT COALESCE(MAX(generation), 0) + 1 AS generation
        FROM mercury_management.endpoint_signing_credentials
        WHERE tenant_id = ${rotation.tenantId}
          AND endpoint_id = ${rotation.endpointId}
      `;
      const generation = numberValue((generationRows[0] as DbRow).generation);
      const inserted = await transaction<DbRow[]>`
        INSERT INTO mercury_management.endpoint_signing_credentials
          (id, account_id, tenant_id, endpoint_id, generation, secret_pointer,
           status, last_confirmed_at, overlap_until, created_at)
        VALUES
          (${rotation.id}, ${rotation.accountId}, ${rotation.tenantId},
           ${rotation.endpointId}, ${generation}, ${rotation.secretPointer},
           'live', ${rotation.rotatedAt}, NULL, ${rotation.rotatedAt})
        RETURNING *
      `;
      if (endpointRow !== undefined) {
        const rebound = await transaction<DbRow[]>`
          UPDATE mercury_management.endpoints
          SET signing_credential_id = ${rotation.id},
              updated_at = ${rotation.rotatedAt}
          WHERE id = ${rotation.endpointId}
            AND signing_credential_id = ${rotation.expectedCurrentCredentialId as string}
          RETURNING id
        `;
        if (rebound.length !== 1) {
          throw new ManagementError('conflict', 'endpoint signing credential changed during rotation');
        }
      }
      const overlapped = await transaction<DbRow[]>`
        UPDATE mercury_management.endpoint_signing_credentials
        SET status = 'overlap',
            last_confirmed_at = ${rotation.rotatedAt},
            overlap_until = ${rotation.overlapUntil}
        WHERE tenant_id = ${rotation.tenantId}
          AND endpoint_id = ${rotation.endpointId}
          AND id <> ${rotation.id}
          AND status = 'live'
        RETURNING id
      `;
      if (
        endpointRow !== undefined &&
        !overlapped.some(row => stringValue(row.id) === rotation.expectedCurrentCredentialId)
      ) {
        throw new ManagementError('conflict', 'endpoint signing credential changed during rotation');
      }
      return inserted;
    });
    return endpointSigningCredentialFrom(rows[0] as DbRow);
  }

  public async getCustomDomain(id: string): Promise<CustomDomain | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.custom_domains WHERE id = ${id}
    `;
    return first(rows, domainFrom);
  }

  public async findCustomDomainByHostname(hostname: string): Promise<CustomDomain | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.custom_domains
      WHERE hostname = ${hostname}
    `;
    return first(rows, domainFrom);
  }

  public async listCustomDomains(tenantId: string): Promise<readonly CustomDomain[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.custom_domains
      WHERE tenant_id = ${tenantId}
      ORDER BY hostname
    `;
    return rows.map(domainFrom);
  }

  public async saveCustomDomain(domain: CustomDomain): Promise<CustomDomain> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.custom_domains
        (id, tenant_id, hostname, registered_url, intake_target, challenge_target,
         certificate_secret_pointer, status, verification_token_hash,
         pending_until, verified_at, activated_at, created_at, updated_at)
      VALUES
        (${domain.id}, ${domain.tenantId}, ${domain.hostname},
         ${domain.registeredUrl}, ${domain.intakeTarget}, ${domain.challengeTarget},
         ${domain.certificateSecretPointer}, ${domain.status}, ${domain.verificationTokenHash},
         ${domain.pendingUntil}, ${domain.verifiedAt ?? null}, ${domain.activatedAt ?? null},
         ${domain.createdAt}, ${domain.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        registered_url = EXCLUDED.registered_url,
        intake_target = EXCLUDED.intake_target,
        challenge_target = EXCLUDED.challenge_target,
        certificate_secret_pointer = EXCLUDED.certificate_secret_pointer,
        status = EXCLUDED.status,
        verification_token_hash = EXCLUDED.verification_token_hash,
        pending_until = EXCLUDED.pending_until,
        verified_at = EXCLUDED.verified_at,
        activated_at = EXCLUDED.activated_at,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return domainFrom(rows[0] as DbRow);
  }

  public async deleteCustomDomain(id: string): Promise<boolean> {
    const rows = await this.sql<DbRow[]>`
      DELETE FROM mercury_management.custom_domains WHERE id = ${id}
      RETURNING id
    `;
    return rows.length > 0;
  }

  public async getRoute(id: string): Promise<Route | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.routes WHERE id = ${id}
    `;
    return first(rows, routeFrom);
  }

  public async findRouteByPath(tenantId: string, path: string): Promise<Route | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.routes
      WHERE tenant_id = ${tenantId} AND path = ${path}
    `;
    return first(rows, routeFrom);
  }

  public async listRoutes(tenantId: string): Promise<readonly Route[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.routes
      WHERE tenant_id = ${tenantId}
      ORDER BY path
    `;
    return rows.map(routeFrom);
  }

  public async saveRoute(route: Route): Promise<Route> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.routes
        (id, tenant_id, path, registered_url, provider, scheme,
         provider_credential_id, created_at, updated_at)
      VALUES
        (${route.id}, ${route.tenantId}, ${route.path},
         ${route.registeredUrl}, ${route.provider}, ${route.scheme ?? null},
         ${route.providerCredentialId ?? null},
         ${route.createdAt}, ${route.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        provider = EXCLUDED.provider,
        registered_url = EXCLUDED.registered_url,
        scheme = EXCLUDED.scheme,
        provider_credential_id = EXCLUDED.provider_credential_id,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return routeFrom(rows[0] as DbRow);
  }

  public async deleteRoute(id: string): Promise<boolean> {
    const rows = await this.sql<DbRow[]>`
      DELETE FROM mercury_management.routes WHERE id = ${id} RETURNING id
    `;
    return rows.length > 0;
  }

  public async getEndpoint(id: string): Promise<Endpoint | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.endpoints WHERE id = ${id}
    `;
    return first(rows, endpointFrom);
  }

  public async listEndpoints(routeId: string): Promise<readonly Endpoint[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.endpoints
      WHERE route_id = ${routeId}
      ORDER BY id
    `;
    return rows.map(endpointFrom);
  }

  public async saveEndpoint(endpoint: Endpoint): Promise<Endpoint> {
    const targetUrl = endpoint.target.kind === 'url' ? endpoint.target.url : null;
    const targetService = endpoint.target.kind === 'coordinate' ? endpoint.target.service : null;
    const targetModule = endpoint.target.kind === 'coordinate' ? endpoint.target.module : null;
    const canonicalVlandscape = endpoint.target.kind === 'coordinate' ? endpoint.target.canonicalVlandscape : null;
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.endpoints
        (id, route_id, target_kind, target_url, target_service, target_module,
         canonical_vlandscape, signing_credential_id, circuit_state,
         circuit_opened_at, last_probe_at, last_probe_succeeded_at,
         created_at, updated_at)
      VALUES
        (${endpoint.id}, ${endpoint.routeId}, ${endpoint.target.kind},
         ${targetUrl}, ${targetService}, ${targetModule},
         ${canonicalVlandscape}, ${endpoint.signingCredentialId},
         ${endpoint.circuitState}, ${endpoint.circuitOpenedAt ?? null},
         ${endpoint.lastProbeAt ?? null},
         ${endpoint.lastProbeSucceededAt ?? null}, ${endpoint.createdAt},
         ${endpoint.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        target_kind = EXCLUDED.target_kind,
        target_url = EXCLUDED.target_url,
        target_service = EXCLUDED.target_service,
        target_module = EXCLUDED.target_module,
        canonical_vlandscape = EXCLUDED.canonical_vlandscape,
        signing_credential_id = EXCLUDED.signing_credential_id,
        circuit_state = EXCLUDED.circuit_state,
        circuit_opened_at = EXCLUDED.circuit_opened_at,
        last_probe_at = EXCLUDED.last_probe_at,
        last_probe_succeeded_at = EXCLUDED.last_probe_succeeded_at,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return endpointFrom(rows[0] as DbRow);
  }

  public async deleteEndpoint(id: string): Promise<boolean> {
    const rows = await this.sql<DbRow[]>`
      DELETE FROM mercury_management.endpoints WHERE id = ${id} RETURNING id
    `;
    return rows.length > 0;
  }

  public async listSubscriptions(tenantId: string): Promise<readonly SubscriptionRegistration[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.subscription_registrations
      WHERE tenant_id = ${tenantId}
      ORDER BY provider, external_id
    `;
    return rows.map(subscriptionFrom);
  }

  public async saveSubscription(subscription: SubscriptionRegistration): Promise<SubscriptionRegistration> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.subscription_registrations
        (id, tenant_id, provider, external_id, retention_seconds,
         dead_letter_target, metadata, created_at, updated_at)
      VALUES
        (${subscription.id}, ${subscription.tenantId},
         ${subscription.provider}, ${subscription.externalId},
         ${subscription.retentionSeconds ?? null},
         ${subscription.deadLetterTarget ?? null},
         ${this.sql.json(subscription.metadata as postgres.JSONValue)},
         ${subscription.createdAt}, ${subscription.updatedAt})
      ON CONFLICT (id) DO UPDATE SET
        retention_seconds = EXCLUDED.retention_seconds,
        dead_letter_target = EXCLUDED.dead_letter_target,
        metadata = EXCLUDED.metadata,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return subscriptionFrom(rows[0] as DbRow);
  }

  public async listLandscapeEventSources(accountId: string): Promise<readonly LandscapeEventSource[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.landscape_event_sources
      WHERE account_id = ${accountId}
      ORDER BY landscape
    `;
    return rows.map(sourceFrom);
  }

  public async saveLandscapeEventSource(source: LandscapeEventSource): Promise<LandscapeEventSource> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.landscape_event_sources
        (account_id, landscape, query_url, replay_url, credential_pointer, enabled,
         updated_at)
      VALUES
        (${source.accountId}, ${source.landscape}, ${source.queryUrl}, ${source.replayUrl},
         ${source.credentialPointer}, ${source.enabled}, ${source.updatedAt})
      ON CONFLICT (account_id, landscape) DO UPDATE SET
        query_url = EXCLUDED.query_url,
        replay_url = EXCLUDED.replay_url,
        credential_pointer = EXCLUDED.credential_pointer,
        enabled = EXCLUDED.enabled,
        updated_at = EXCLUDED.updated_at
      RETURNING *
    `;
    return sourceFrom(rows[0] as DbRow);
  }

  public async saveReplayAudit(audit: ReplayAudit): Promise<ReplayAudit> {
    const eventId = audit.scope.kind === 'event' ? audit.scope.eventId : null;
    const endpointId = audit.scope.kind === 'endpoint' ? audit.scope.endpointId : null;
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.replay_audit
        (id, account_id, tenant_id, landscape, scope_kind, event_id,
         endpoint_id, reason, command_id, requested_at)
      VALUES
        (${audit.id}, ${audit.accountId}, ${audit.tenantId},
         ${audit.landscape}, ${audit.scope.kind}, ${eventId}, ${endpointId},
         ${audit.reason}, ${audit.commandId}, ${audit.requestedAt})
      RETURNING *
    `;
    return replayFrom(rows[0] as DbRow);
  }

  public async listReplayAudits(tenantId: string): Promise<readonly ReplayAudit[]> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.replay_audit
      WHERE tenant_id = ${tenantId}
      ORDER BY requested_at
    `;
    return rows.map(replayFrom);
  }

  public async nextConfigGeneration(): Promise<number> {
    const rows = await this.sql<DbRow[]>`
      SELECT nextval('mercury_management.config_generation_seq') AS generation
    `;
    return numberValue((rows[0] as DbRow).generation);
  }

  public async saveConfigGeneration(generation: ConfigGeneration): Promise<ConfigGeneration> {
    const rows = await this.sql.begin(async transaction => {
      if (generation.status === 'active') {
        await transaction`
          UPDATE mercury_management.config_generations
          SET status = 'superseded'
          WHERE landscape = ${generation.landscape}
            AND status = 'active'
            AND generation <> ${generation.generation}
        `;
      }
      return transaction<DbRow[]>`
        INSERT INTO mercury_management.config_generations
          (generation, landscape, status, content_hash, previous_generation,
           grace_until, created_at, activated_at)
        VALUES
          (${generation.generation}, ${generation.landscape},
           ${generation.status},
           ${generation.contentHash}, ${generation.previousGeneration ?? null},
           ${generation.graceUntil ?? null}, ${generation.createdAt},
           ${generation.activatedAt ?? null})
        ON CONFLICT (generation) DO UPDATE SET
          status = EXCLUDED.status,
          content_hash = EXCLUDED.content_hash,
          previous_generation = EXCLUDED.previous_generation,
          grace_until = EXCLUDED.grace_until,
          activated_at = EXCLUDED.activated_at
        WHERE config_generations.landscape = EXCLUDED.landscape
        RETURNING *
      `;
    });
    if (rows[0] === undefined) {
      throw new ManagementError('conflict', 'configuration generation landscape is immutable', {
        generation: generation.generation,
        requestedLandscape: generation.landscape,
      });
    }
    return generationFrom(rows[0] as DbRow);
  }

  public async getConfigGeneration(generation: number): Promise<ConfigGeneration | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.config_generations
      WHERE generation = ${generation}
    `;
    return first(rows, generationFrom);
  }

  public async getActiveConfigGeneration(landscape: string): Promise<ConfigGeneration | undefined> {
    const rows = await this.sql<DbRow[]>`
      SELECT * FROM mercury_management.config_generations
      WHERE landscape = ${landscape} AND status = 'active'
      ORDER BY generation DESC LIMIT 1
    `;
    return first(rows, generationFrom);
  }

  public async listConfigGenerations(landscape?: string): Promise<readonly ConfigGeneration[]> {
    const rows =
      landscape === undefined
        ? await this.sql<DbRow[]>`
            SELECT * FROM mercury_management.config_generations
            ORDER BY generation
          `
        : await this.sql<DbRow[]>`
            SELECT * FROM mercury_management.config_generations
            WHERE landscape = ${landscape}
            ORDER BY generation
          `;
    return rows.map(generationFrom);
  }

  public async saveLandscapeAcknowledgement(
    acknowledgement: LandscapeAcknowledgement,
  ): Promise<LandscapeAcknowledgement> {
    const rows = await this.sql<DbRow[]>`
      INSERT INTO mercury_management.landscape_config_acknowledgements
        (landscape, generation, acknowledged_at, content_hash)
      VALUES
        (${acknowledgement.landscape}, ${acknowledgement.generation},
         ${acknowledgement.acknowledgedAt}, ${acknowledgement.contentHash})
      ON CONFLICT (landscape, generation) DO UPDATE SET
        acknowledged_at = EXCLUDED.acknowledged_at,
        content_hash = EXCLUDED.content_hash
      RETURNING *
    `;
    return acknowledgementFrom(rows[0] as DbRow);
  }

  public async listLandscapeAcknowledgements(generation?: number): Promise<readonly LandscapeAcknowledgement[]> {
    const rows =
      generation === undefined
        ? await this.sql<DbRow[]>`
            SELECT *
            FROM mercury_management.landscape_config_acknowledgements
            ORDER BY generation, landscape
          `
        : await this.sql<DbRow[]>`
            SELECT *
            FROM mercury_management.landscape_config_acknowledgements
            WHERE generation = ${generation}
            ORDER BY landscape
          `;
    return rows.map(acknowledgementFrom);
  }

  public async listTenantConfigurations(): Promise<readonly TenantConfiguration[]> {
    const output: TenantConfiguration[] = [];
    for (const tenant of await this.listTenants()) {
      const account = await this.getAccount(tenant.accountId);
      const quota = await this.getQuota(tenant.id);
      const metering = await this.getMeteringConfiguration(tenant.id);
      if (account === undefined || quota === undefined || metering === undefined) {
        continue;
      }
      const routes = [];
      for (const route of await this.listRoutes(tenant.id)) {
        routes.push({
          route,
          endpoints: await this.listEndpoints(route.id),
        });
      }
      output.push({
        tenant,
        account,
        quota,
        metering,
        domains: await this.listCustomDomains(tenant.id),
        providerCredentials: await this.listProviderCredentials(tenant.id),
        endpointSigningCredentials: await this.listEndpointSigningCredentials(tenant.id),
        routes,
      });
    }
    return output;
  }
}
