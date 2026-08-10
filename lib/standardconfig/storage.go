package standardconfig

// StorageBlockKey is the frozen root key the storage preset mounts under
// (C0 §3).
const StorageBlockKey = "storage"

// StorageEntry is one named S3-compatible object-storage endpoint.
//
// Provider-agnostic: Tigris in cloud landscapes, MinIO locally, both addressed
// through the same block. ForcePathStyle is the one field that differs between
// them in practice.
type StorageEntry struct {
	// Endpoint is the S3-compatible endpoint URL.
	Endpoint string `json:"endpoint" yaml:"endpoint"`
	// Region is the region label the endpoint expects.
	Region string `json:"region" yaml:"region"`
	// Bucket is the bucket name.
	Bucket string `json:"bucket" yaml:"bucket"`
	// AccessKeyID is a secret: blank in YAML, injected per landscape (R14/M33).
	AccessKeyID string `json:"accessKeyId" yaml:"accessKeyId"`
	// SecretAccessKey is a secret: blank in YAML, injected per landscape
	// (R14/M33).
	SecretAccessKey string `json:"secretAccessKey" yaml:"secretAccessKey"`
	// ForcePathStyle selects path-style addressing: true for MinIO and other
	// path-style endpoints, false for virtual-hosted-style providers.
	ForcePathStyle bool `json:"forcePathStyle" yaml:"forcePathStyle"`
}

// StorageBlock is the resolved storage preset: named S3-compatible endpoints
// keyed by their UPPERCASE pool name.
type StorageBlock = map[string]StorageEntry

// StorageSchema returns the draft-2020-12 JSON Schema fragment for the storage
// preset.
//
// C0-FROZEN (C0 §3): matched key-for-key by the bun and dotnet standard-config
// siblings.
func StorageSchema() map[string]any {
	return keyedSchema(
		"Named S3-compatible object-storage endpoints, keyed by UPPERCASE pool name (R14).",
		objectSchema("One named S3-compatible storage connection.", map[string]any{
			"endpoint":        nonBlankSchema("S3-compatible endpoint URL."),
			"region":          nonBlankSchema("Region label the endpoint expects."),
			"bucket":          nonBlankSchema("Bucket name."),
			"accessKeyId":     secretSchema("Access key id."),
			"secretAccessKey": secretSchema("Secret access key."),
			"forcePathStyle":  boolSchema("Use path-style addressing (true for MinIO)."),
		}),
	)
}
