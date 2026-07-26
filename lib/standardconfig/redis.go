package standardconfig

// RedisEntry is the Redis-protocol connection shape shared by the cache and kv
// presets.
//
// Cache (Dragonfly) and kv (Upstash in cloud landscapes, snapshot-durable
// Dragonfly locally) both speak the Redis protocol, so their CONNECTION fields
// are identical. Sharing this entry type is an internal convenience: they stay
// SEPARATE presets under separate root keys because their durability semantics
// differ, and the rule that a cache instance may never be relabelled as kv
// holds at the block boundary, not at the field list.
type RedisEntry struct {
	// Host is the hostname of the Redis-protocol endpoint.
	Host string `json:"host" yaml:"host"`
	// Port is the TCP port.
	Port int `json:"port" yaml:"port"`
	// Password is a secret: blank in YAML, injected per landscape (R14/M33).
	Password string `json:"password" yaml:"password"`
	// DB is the logical database index selected on connect.
	DB int `json:"db" yaml:"db"`
	// TLS requires TLS on the connection.
	TLS bool `json:"tls" yaml:"tls"`
}

// redisEntrySchema returns the entry fragment both Redis-protocol presets
// mount. The two presets call it separately so each carries its own durability
// wording rather than a shared, vaguer one.
func redisEntrySchema(description string) map[string]any {
	return objectSchema(description, map[string]any{
		"host":     hostSchema("Hostname of the Redis-protocol endpoint."),
		"port":     portSchema("TCP port of the Redis-protocol endpoint."),
		"password": secretSchema("Endpoint password."),
		"db":       countSchema(0, "Logical database index selected on connect."),
		"tls":      boolSchema("Require TLS on the connection."),
	})
}
