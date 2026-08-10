package testhelper

import "github.com/AtomiCloud/diene.go-config/lib/config"

// BaseSource returns an in-memory base YAML layer for document.
func BaseSource(document string) config.YAMLSource {
	return config.NewBytesYAMLSource("testhelper:base", []byte(document))
}

// OverlaySource returns an in-memory overlay YAML layer for landscape.
func OverlaySource(landscape, document string) config.YAMLSource {
	return config.NewBytesYAMLSource("testhelper:overlay:"+landscape, []byte(document))
}

// EnvSource returns an in-memory env layer over vars, so the final layer is
// driven deterministically without os.Setenv.
func EnvSource(vars map[string]string) config.EnvSource {
	return config.NewMapEnvSource("testhelper:env", vars)
}
