CREATE SCHEMA IF NOT EXISTS mercury_management;

CREATE TYPE mercury_management.account_kind AS ENUM ('internal', 'external');
CREATE TYPE mercury_management.account_status AS ENUM ('active', 'suspended');
CREATE TYPE mercury_management.tenant_source AS ENUM ('api', 'cr');
CREATE TYPE mercury_management.credential_kind AS ENUM (
  'management',
  'intake',
  'delivery_signing',
  'provider_verification'
);
CREATE TYPE mercury_management.credential_status AS ENUM (
  'planned',
  'live',
  'overlap',
  'revoked'
);
CREATE TYPE mercury_management.domain_status AS ENUM (
  'pending',
  'verified',
  'active',
  'failed'
);
CREATE TYPE mercury_management.circuit_state AS ENUM (
  'closed',
  'open',
  'probing'
);
CREATE TYPE mercury_management.generation_status AS ENUM (
  'writing',
  'activated',
  'active',
  'superseded',
  'failed'
);

CREATE TABLE mercury_management.accounts (
  id uuid PRIMARY KEY,
  name text NOT NULL UNIQUE,
  kind mercury_management.account_kind NOT NULL,
  status mercury_management.account_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  CONSTRAINT accounts_name_partition CHECK (
    (kind = 'internal' AND name LIKE 'internal/%')
    OR (kind = 'external' AND name LIKE 'external/%')
  )
);

CREATE TABLE mercury_management.tenants (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES mercury_management.accounts(id),
  name text NOT NULL UNIQUE,
  intake_slug text NOT NULL UNIQUE,
  source mercury_management.tenant_source NOT NULL,
  home_vlandscape text NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE (id, account_id),
  CONSTRAINT tenants_name_partition CHECK (
    (source = 'cr' AND name LIKE 'internal/%')
    OR (source = 'api' AND name LIKE 'external/%')
  ),
  CONSTRAINT tenants_home_nonempty CHECK (length(home_vlandscape) > 0)
);

-- There is deliberately no UPDATE trigger or API for home_vlandscape. The
-- repository uses an immutable upsert guard and this trigger makes the law
-- hold even for out-of-band SQL clients.
CREATE FUNCTION mercury_management.reject_tenant_home_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.home_vlandscape IS DISTINCT FROM OLD.home_vlandscape
     OR NEW.intake_slug IS DISTINCT FROM OLD.intake_slug THEN
    RAISE EXCEPTION 'tenant home_vlandscape and intake_slug are immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tenants_immutable_home
BEFORE UPDATE ON mercury_management.tenants
FOR EACH ROW EXECUTE FUNCTION mercury_management.reject_tenant_home_change();

CREATE TABLE mercury_management.quotas (
  tenant_id uuid PRIMARY KEY REFERENCES mercury_management.tenants(id) ON DELETE CASCADE,
  intake_rps integer NOT NULL CHECK (intake_rps > 0),
  burst integer NOT NULL CHECK (burst > 0),
  management_rps integer NOT NULL CHECK (management_rps > 0),
  retry_window_seconds integer NOT NULL CHECK (
    retry_window_seconds > 0 AND retry_window_seconds <= 259200
  ),
  dedup_window_seconds integer NOT NULL CHECK (dedup_window_seconds = 259200),
  retention_months integer NOT NULL CHECK (retention_months > 0),
  updated_at timestamptz NOT NULL
);

CREATE TABLE mercury_management.metering_configuration (
  tenant_id uuid PRIMARY KEY REFERENCES mercury_management.tenants(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  export_interval_seconds integer NOT NULL CHECK (export_interval_seconds > 0),
  dimensions text[] NOT NULL DEFAULT '{intake,delivery,replay,archive_bytes}',
  billing_account_reference text,
  updated_at timestamptz NOT NULL
);

CREATE TABLE mercury_management.native_credentials (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES mercury_management.accounts(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES mercury_management.tenants(id),
  kind mercury_management.credential_kind NOT NULL,
  generation integer NOT NULL CHECK (generation > 0),
  token_hash text,
  secret_pointer text,
  scopes text[] NOT NULL DEFAULT '{}',
  status mercury_management.credential_status NOT NULL,
  live_from timestamptz,
  last_confirmed_at timestamptz,
  overlap_until timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL,
  UNIQUE (account_id, tenant_id, kind, generation),
  CONSTRAINT native_credentials_material CHECK (
    token_hash IS NOT NULL OR secret_pointer IS NOT NULL
  ),
  CONSTRAINT native_credentials_pointer_shape CHECK (
    secret_pointer IS NULL OR (
      secret_pointer ~ '^/[A-Za-z0-9._-]{1,253}$'
      AND secret_pointer NOT IN ('/.', '/..')
    )
  )
);

CREATE UNIQUE INDEX native_credentials_token_hash
ON mercury_management.native_credentials(token_hash)
WHERE token_hash IS NOT NULL;

CREATE TABLE mercury_management.management_rate_windows (
  credential_id uuid NOT NULL REFERENCES mercury_management.native_credentials(id) ON DELETE CASCADE,
  window_second bigint NOT NULL,
  cost integer NOT NULL CHECK (cost > 0),
  PRIMARY KEY (credential_id, window_second)
);

CREATE TABLE mercury_management.provider_credentials (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  tenant_id uuid NOT NULL,
  provider text NOT NULL,
  generation integer NOT NULL CHECK (generation > 0),
  secret_pointer text NOT NULL CHECK (
    secret_pointer ~ '^/[A-Za-z0-9._-]{1,253}$' AND secret_pointer NOT IN ('/.', '/..')
  ),
  status mercury_management.credential_status NOT NULL,
  last_confirmed_at timestamptz,
  overlap_until timestamptz,
  created_at timestamptz NOT NULL,
  UNIQUE (tenant_id, provider, generation),
  UNIQUE (id, tenant_id, provider),
  FOREIGN KEY (tenant_id, account_id)
    REFERENCES mercury_management.tenants(id, account_id)
);

CREATE TABLE mercury_management.endpoint_signing_credentials (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  tenant_id uuid NOT NULL,
  endpoint_id uuid NOT NULL,
  generation integer NOT NULL CHECK (generation > 0),
  secret_pointer text NOT NULL CHECK (
    secret_pointer ~ '^/[A-Za-z0-9._-]{1,253}$' AND secret_pointer NOT IN ('/.', '/..')
  ),
  status mercury_management.credential_status NOT NULL,
  last_confirmed_at timestamptz,
  overlap_until timestamptz,
  created_at timestamptz NOT NULL,
  UNIQUE (tenant_id, endpoint_id, generation),
  FOREIGN KEY (tenant_id, account_id)
    REFERENCES mercury_management.tenants(id, account_id)
);

CREATE TABLE mercury_management.custom_domains (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES mercury_management.tenants(id),
  hostname text NOT NULL UNIQUE,
  registered_url text NOT NULL,
  intake_target text NOT NULL,
  challenge_target text NOT NULL,
  certificate_secret_pointer text NOT NULL CHECK (
    certificate_secret_pointer ~ '^/[A-Za-z0-9._-]{1,253}$'
    AND certificate_secret_pointer NOT IN ('/.', '/..')
  ),
  status mercury_management.domain_status NOT NULL,
  verification_token_hash text NOT NULL,
  pending_until timestamptz NOT NULL,
  verified_at timestamptz,
  activated_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE mercury_management.routes (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES mercury_management.tenants(id),
  path text NOT NULL,
  registered_url text NOT NULL,
  provider text NOT NULL,
  scheme text,
  provider_credential_id uuid,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE (tenant_id, path),
  FOREIGN KEY (provider_credential_id, tenant_id, provider)
    REFERENCES mercury_management.provider_credentials(id, tenant_id, provider),
  CONSTRAINT route_path_shape CHECK (path LIKE '/%')
);

CREATE TABLE mercury_management.endpoints (
  id uuid PRIMARY KEY,
  route_id uuid NOT NULL REFERENCES mercury_management.routes(id) ON DELETE CASCADE,
  target_kind text NOT NULL CHECK (target_kind IN ('coordinate', 'url')),
  target_url text,
  target_service text,
  target_module text,
  canonical_vlandscape text,
  signing_credential_id uuid NOT NULL REFERENCES mercury_management.endpoint_signing_credentials(id),
  circuit_state mercury_management.circuit_state NOT NULL DEFAULT 'closed',
  circuit_opened_at timestamptz,
  last_probe_at timestamptz,
  last_probe_succeeded_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  CONSTRAINT endpoint_target_shape CHECK (
    (
      target_kind = 'url'
      AND target_url IS NOT NULL
      AND target_service IS NULL
      AND target_module IS NULL
      AND canonical_vlandscape IS NULL
    )
    OR (
      target_kind = 'coordinate'
      AND target_url IS NULL
      AND target_service IS NOT NULL
      AND target_module IS NOT NULL
      AND canonical_vlandscape IS NOT NULL
    )
  )
);

CREATE FUNCTION mercury_management.enforce_endpoint_signing_ownership()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  endpoint_tenant uuid;
BEGIN
  SELECT routes.tenant_id INTO endpoint_tenant
  FROM mercury_management.routes
  WHERE routes.id = NEW.route_id;
  IF NOT EXISTS (
    SELECT 1
    FROM mercury_management.endpoint_signing_credentials credentials
    WHERE credentials.id = NEW.signing_credential_id
      AND credentials.tenant_id = endpoint_tenant
      AND credentials.endpoint_id = NEW.id
      AND credentials.status = 'live'
  ) THEN
    RAISE EXCEPTION 'endpoint signing credential ownership mismatch';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER endpoints_signing_ownership
BEFORE INSERT OR UPDATE OF route_id, signing_credential_id
ON mercury_management.endpoints
FOR EACH ROW EXECUTE FUNCTION mercury_management.enforce_endpoint_signing_ownership();

CREATE FUNCTION mercury_management.enforce_management_cardinality()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  tenant uuid;
BEGIN
  IF TG_TABLE_NAME = 'accounts' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('mercury:accounts', 0));
    IF (SELECT count(*) FROM mercury_management.accounts) >= 1000 THEN
      RAISE EXCEPTION 'account hard cap exceeded';
    END IF;
  ELSIF TG_TABLE_NAME = 'tenants' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('mercury:tenants:' || NEW.account_id::text, 0));
    IF (SELECT count(*) FROM mercury_management.tenants WHERE account_id = NEW.account_id) >= 128 THEN
      RAISE EXCEPTION 'tenant hard cap exceeded';
    END IF;
  ELSIF TG_TABLE_NAME = 'routes' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('mercury:routes:' || NEW.tenant_id::text, 0));
    IF (SELECT count(*) FROM mercury_management.routes WHERE tenant_id = NEW.tenant_id) >= 64 THEN
      RAISE EXCEPTION 'route hard cap exceeded';
    END IF;
  ELSIF TG_TABLE_NAME = 'endpoints' THEN
    SELECT routes.tenant_id INTO tenant
    FROM mercury_management.routes
    WHERE routes.id = NEW.route_id;
    PERFORM pg_advisory_xact_lock(hashtextextended('mercury:endpoints:' || tenant::text, 0));
    IF (SELECT count(*) FROM mercury_management.endpoints WHERE route_id = NEW.route_id) >= 64 THEN
      RAISE EXCEPTION 'endpoint hard cap exceeded';
    END IF;
    IF (
      SELECT count(*)
      FROM mercury_management.endpoints endpoints
      JOIN mercury_management.routes routes ON routes.id = endpoints.route_id
      WHERE routes.tenant_id = tenant
    ) >= 512 THEN
      RAISE EXCEPTION 'tenant fan-out hard cap exceeded';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER accounts_hard_cap
BEFORE INSERT ON mercury_management.accounts
FOR EACH ROW EXECUTE FUNCTION mercury_management.enforce_management_cardinality();
CREATE TRIGGER tenants_hard_cap
BEFORE INSERT ON mercury_management.tenants
FOR EACH ROW EXECUTE FUNCTION mercury_management.enforce_management_cardinality();
CREATE TRIGGER routes_hard_cap
BEFORE INSERT ON mercury_management.routes
FOR EACH ROW EXECUTE FUNCTION mercury_management.enforce_management_cardinality();
CREATE TRIGGER endpoints_hard_cap
BEFORE INSERT ON mercury_management.endpoints
FOR EACH ROW EXECUTE FUNCTION mercury_management.enforce_management_cardinality();

CREATE TABLE mercury_management.subscription_registrations (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES mercury_management.tenants(id),
  provider text NOT NULL,
  external_id text NOT NULL,
  retention_seconds integer CHECK (retention_seconds > 0),
  dead_letter_target text,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE (tenant_id, provider, external_id)
);

CREATE TABLE mercury_management.landscape_event_sources (
  account_id uuid NOT NULL REFERENCES mercury_management.accounts(id) ON DELETE CASCADE,
  landscape text NOT NULL,
  query_url text NOT NULL,
  replay_url text NOT NULL,
  credential_pointer text NOT NULL CHECK (
    credential_pointer ~ '^/[A-Za-z0-9._-]{1,253}$' AND credential_pointer NOT IN ('/.', '/..')
  ),
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, landscape)
);

CREATE TABLE mercury_management.replay_audit (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES mercury_management.accounts(id),
  tenant_id uuid NOT NULL REFERENCES mercury_management.tenants(id),
  landscape text NOT NULL,
  scope_kind text NOT NULL CHECK (scope_kind IN ('event', 'endpoint')),
  event_id text,
  endpoint_id uuid REFERENCES mercury_management.endpoints(id),
  reason text NOT NULL,
  command_id text NOT NULL UNIQUE,
  requested_at timestamptz NOT NULL,
  CONSTRAINT replay_scope_shape CHECK (
    (scope_kind = 'event' AND event_id IS NOT NULL AND endpoint_id IS NULL)
    OR
    (scope_kind = 'endpoint' AND event_id IS NULL AND endpoint_id IS NOT NULL)
  )
);

CREATE SEQUENCE mercury_management.config_generation_seq;

CREATE TABLE mercury_management.config_generations (
  generation bigint PRIMARY KEY,
  landscape text NOT NULL,
  status mercury_management.generation_status NOT NULL,
  content_hash text NOT NULL,
  previous_generation bigint,
  grace_until timestamptz,
  created_at timestamptz NOT NULL,
  activated_at timestamptz,
  UNIQUE (landscape, generation),
  FOREIGN KEY (landscape, previous_generation)
    REFERENCES mercury_management.config_generations(landscape, generation)
);

CREATE FUNCTION mercury_management.reject_config_generation_landscape_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.landscape IS DISTINCT FROM OLD.landscape THEN
    RAISE EXCEPTION 'configuration generation landscape is immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER config_generations_immutable_landscape
BEFORE UPDATE ON mercury_management.config_generations
FOR EACH ROW EXECUTE FUNCTION mercury_management.reject_config_generation_landscape_change();

CREATE UNIQUE INDEX config_one_active_generation_per_landscape
ON mercury_management.config_generations(landscape)
WHERE status = 'active';

CREATE TABLE mercury_management.landscape_config_acknowledgements (
  landscape text NOT NULL,
  generation bigint NOT NULL,
  acknowledged_at timestamptz NOT NULL,
  content_hash text NOT NULL,
  PRIMARY KEY (landscape, generation),
  FOREIGN KEY (landscape, generation)
    REFERENCES mercury_management.config_generations(landscape, generation)
);

-- Q-WH7: provisioning always creates the ordinary default internal account.
-- Credentials are minted out-of-band and stored only as hashes/pointers.
INSERT INTO mercury_management.accounts (
  id,
  name,
  kind,
  status,
  created_at,
  updated_at
) VALUES (
  '00000000-0000-4000-8000-000000000001',
  'internal/default',
  'internal',
  'active',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
) ON CONFLICT (name) DO NOTHING;
