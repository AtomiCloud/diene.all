package appconfig

const (
	PostgresMain   = "MAIN"
	CacheMain      = "MAIN"
	KvMain         = "MAIN"
	StorageMain    = "MAIN"
	StorageArchive = "ARCHIVE"
)

// KeyedAdapterConstants returns the connection names compiled into the composition root.
func KeyedAdapterConstants() map[string][]string {
	return map[string][]string{
		"cache":    {CacheMain},
		"kv":       {KvMain},
		"postgres": {PostgresMain},
		"storage":  {StorageArchive, StorageMain},
	}
}
