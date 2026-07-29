package standardconfig

// KvBlockKey is the frozen root key the kv preset mounts under (C0 §3).
const KvBlockKey = "kv"

// KvEntry is one named key-value connection.
//
// kv is PERSISTENT: Upstash in cloud landscapes, and locally a Dragonfly
// instance configured with SNAPSHOT durability — a distinct instance, never a
// relabelling of the [CacheEntry] one. The Redis protocol is shared; the
// durability contract is not.
type KvEntry = RedisEntry

// KvBlock is the resolved kv preset: named persistent kv endpoints keyed by
// their UPPERCASE pool name.
type KvBlock = map[string]KvEntry

// KvSchema returns the draft-2020-12 JSON Schema fragment for the kv preset.
//
// C0-FROZEN (C0 §3): matched key-for-key by the bun and dotnet standard-config
// siblings.
func KvSchema() map[string]any {
	return keyedSchema(
		"Named persistent key-value endpoints, keyed by UPPERCASE pool name (R14).",
		redisEntrySchema("One named kv connection. PERSISTENT — a separate instance from any cache."),
	)
}
