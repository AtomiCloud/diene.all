import { describe, expect, test } from 'bun:test';

const migration = await Bun.file(new URL('../../../migrations/001_mercury_management.sql', import.meta.url)).text();

describe('Neon management migration shape', () => {
  test('owns every durable management-plane aggregate', () => {
    for (const table of [
      'accounts',
      'tenants',
      'quotas',
      'metering_configuration',
      'native_credentials',
      'management_rate_windows',
      'provider_credentials',
      'endpoint_signing_credentials',
      'custom_domains',
      'routes',
      'endpoints',
      'subscription_registrations',
      'landscape_event_sources',
      'replay_audit',
      'config_generations',
      'landscape_config_acknowledgements',
    ]) {
      expect(migration).toContain(`CREATE TABLE mercury_management.${table}`);
    }
  });

  test('seeds the default internal account and enforces immutable home', () => {
    expect(migration).toContain("'internal/default'");
    expect(migration).toContain('tenants_immutable_home');
    expect(migration).toContain('reject_tenant_home_change');
    expect(migration).toContain('intake_slug text NOT NULL UNIQUE');
    expect(migration).toContain('registered_url text NOT NULL');
    expect(migration).not.toMatch(/^\s*(BEGIN|COMMIT);/m);
  });

  test('scopes generation chains, active uniqueness, and acknowledgements to landscape', () => {
    expect(migration).toContain('landscape text NOT NULL');
    expect(migration).toContain('UNIQUE (landscape, generation)');
    expect(migration).toContain('FOREIGN KEY (landscape, previous_generation)');
    expect(migration).toContain('config_one_active_generation_per_landscape');
    expect(migration).toContain('ON mercury_management.config_generations(landscape)');
    expect(migration).toContain('config_generations_immutable_landscape');
    expect(migration).toContain('FOREIGN KEY (landscape, generation)');
  });

  test('stores pointers and hashes rather than secret values', () => {
    expect(migration).toContain('token_hash');
    expect(migration).toContain('secret_pointer');
    expect(migration).not.toContain('secret_value');
    expect(migration.toLowerCase()).not.toContain('cloudflare');
  });

  test('enforces opaque bindings, account-owned landscape trust, domain proof, and hard caps', () => {
    expect(migration).toContain('provider_credential_id uuid');
    expect(migration).toContain('signing_credential_id uuid NOT NULL');
    expect(migration).not.toContain('provider_credential_pointer');
    expect(migration).not.toContain('signing_secret_pointer');
    expect(migration).toContain('endpoint_signing_ownership');
    expect(migration).toContain('PRIMARY KEY (account_id, landscape)');
    expect(migration).toContain('verification_token_hash text NOT NULL');
    expect(migration).toContain('pending_until timestamptz NOT NULL');
    expect(migration).toContain('enforce_management_cardinality');
    expect(migration).toContain("'activated'");
  });
});
