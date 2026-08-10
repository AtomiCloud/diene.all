package standardconfig

// PostgresBlockKey is the frozen root key the postgres preset mounts under
// (C0 §3).
const PostgresBlockKey = "postgres"

// PoolSizing is the connection-pool sizing of one Postgres connection.
type PoolSizing struct {
	// Min is the number of connections kept open when idle.
	Min int `json:"min" yaml:"min"`
	// Max is the pool ceiling. One service, one landscape, one budget.
	Max int `json:"max" yaml:"max"`
}

// PostgresEntry is one named Postgres connection.
//
// The block is provider-agnostic: Neon, CNPG, and a local container all speak
// this shape, and which provider serves a landscape is the environment matrix's
// business, never the connection block's.
type PostgresEntry struct {
	// Host is the hostname of the Postgres endpoint.
	Host string `json:"host" yaml:"host"`
	// Port is the TCP port.
	Port int `json:"port" yaml:"port"`
	// Database is the database name.
	Database string `json:"database" yaml:"database"`
	// Username is the role name.
	Username string `json:"username" yaml:"username"`
	// Password is a secret: blank in YAML, injected per landscape (R14/M33).
	Password string `json:"password" yaml:"password"`
	// SSL requires TLS on the connection.
	SSL bool `json:"ssl" yaml:"ssl"`
	// Pool is the connection-pool sizing.
	Pool PoolSizing `json:"pool" yaml:"pool"`
}

// PostgresBlock is the resolved postgres preset: named connections keyed by
// their UPPERCASE pool name.
type PostgresBlock = map[string]PostgresEntry

// PostgresSchema returns the draft-2020-12 JSON Schema fragment for the
// postgres preset.
//
// C0-FROZEN (C0 §3): this key set is matched key-for-key by the bun and dotnet
// standard-config siblings. Adding, renaming, or dropping a key here is a
// cross-language contract change, not a local one.
//
// Mount it with config.NewBlock([PostgresBlockKey], required, PostgresSchema())
// and let the config library validate it as part of the composed root schema.
func PostgresSchema() map[string]any {
	return keyedSchema(
		"Named Postgres connections, keyed by UPPERCASE pool name (R14).",
		objectSchema("One named Postgres connection.", map[string]any{
			"host":     hostSchema("Hostname of the Postgres endpoint."),
			"port":     portSchema("TCP port of the Postgres endpoint."),
			"database": nonBlankSchema("Database name."),
			"username": nonBlankSchema("Role name."),
			"password": secretSchema("Role password."),
			"ssl":      boolSchema("Require TLS on the connection."),
			"pool": objectSchema("Connection-pool sizing.", map[string]any{
				"min": countSchema(0, "Connections kept open when idle."),
				"max": countSchema(1, "Pool ceiling."),
			}),
		}),
	)
}
