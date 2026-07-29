package standardconfig

// CacheBlockKey is the frozen root key the cache preset mounts under (C0 §3).
const CacheBlockKey = "cache"

// CacheEntry is one named cache connection.
//
// Cache is RAM-backed and EPHEMERAL (Dragonfly with no disk): losing it must
// never lose durable state. Anything that must survive a restart belongs in the
// kv preset instead — see [KvEntry].
type CacheEntry = RedisEntry

// CacheBlock is the resolved cache preset: named cache endpoints keyed by their
// UPPERCASE pool name.
type CacheBlock = map[string]CacheEntry

// CacheSchema returns the draft-2020-12 JSON Schema fragment for the cache
// preset.
//
// C0-FROZEN (C0 §3): matched key-for-key by the bun and dotnet standard-config
// siblings.
func CacheSchema() map[string]any {
	return keyedSchema(
		"Named ephemeral cache endpoints, keyed by UPPERCASE pool name (R14).",
		redisEntrySchema("One named cache connection. RAM-backed and EPHEMERAL — never durable state."),
	)
}
