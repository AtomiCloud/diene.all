package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-consumer/lib/appconfig"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
)

type problemResource struct {
	APIVersion string                  `json:"apiVersion"`
	Kind       string                  `json:"kind"`
	Metadata   problemResourceMetadata `json:"metadata"`
	Spec       problemResourceSpec     `json:"spec"`
}

type problemResourceMetadata struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

type problemResourceSpec struct {
	Platform  string           `json:"platform"`
	Service   string           `json:"service"`
	Landscape string           `json:"landscape"`
	Version   string           `json:"version"`
	Problems  []map[string]any `json:"problems"`
}

func main() {
	output := flag.String("out", "infra/primordial_chart/files/problems.json", "Problem catalog output path")
	landscape := flag.String("landscape", "", "optional landscape overlay")
	flag.Parse()

	if err := run(*output, *landscape); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(output string, landscape string) error {
	root, err := os.Getwd()
	if err != nil {
		return fail("resolve repository root", err)
	}
	configured, err := loadConfig(context.Background(), root, strings.TrimSpace(landscape))
	if err != nil {
		return fail("load application config", err)
	}
	problems, err := domain.NewProblems(
		configured.ErrorPortal.Portal(),
		configured.Transport.Stream,
		configured.ErrorPortal.Version,
	)
	if err != nil {
		return fail("construct domain problems", err)
	}
	resource := problemResource{
		APIVersion: "atomi.cloud/v1alpha1",
		Kind:       "Problem",
		Metadata: problemResourceMetadata{
			Name: strings.Join([]string{
				configured.App.Service,
				configured.App.Landscape,
				configured.ErrorPortal.Version,
			}, "-"),
			Namespace: configured.App.Platform,
		},
		Spec: problemResourceSpec{
			Platform:  configured.App.Platform,
			Service:   configured.App.Service,
			Landscape: configured.App.Landscape,
			Version:   configured.ErrorPortal.Version,
			Problems:  problems.Catalog().ToCRDContent(),
		},
	}
	encoded, err := json.MarshalIndent(resource, "", "  ")
	if err != nil {
		return fail("marshal Problem catalog", err)
	}
	encoded = append(encoded, '\n')
	target := output
	if !filepath.IsAbs(target) {
		target = filepath.Join(root, target)
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o750); err != nil {
		return fail("create Problem catalog directory", err)
	}
	if err := os.WriteFile(target, encoded, 0o600); err != nil {
		return fail("write Problem catalog", err)
	}
	return nil
}

func loadConfig(ctx context.Context, root string, landscape string) (appconfig.ApplicationConfig, error) {
	configDirectory := filepath.Join(root, "config")
	overlayPaths, err := filepath.Glob(filepath.Join(configDirectory, "*.settings.yaml"))
	if err != nil {
		return appconfig.ApplicationConfig{}, fmt.Errorf("discover config overlays: %w", err)
	}
	overlays := make(map[string]config.YAMLSource, len(overlayPaths))
	for _, path := range overlayPaths {
		name := strings.TrimSuffix(filepath.Base(path), ".settings.yaml")
		overlays[name] = config.NewFileYAMLSource("overlay:"+name, path)
	}
	environment := processEnvironment()
	defaults := map[string]string{
		"ATOMI_AUTH__IDP__MANAGEMENT__CLIENT_ID":     "problem-export",
		"ATOMI_AUTH__IDP__MANAGEMENT__CLIENT_SECRET": "problem-export",
		"ATOMI_AUTH__MINTING__CLIENT_ID":             "problem-export",
		"ATOMI_AUTH__MINTING__CLIENT_SECRET":         "problem-export",
		"ATOMI_ENCRYPTION__KEY":                      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
	}
	for name, value := range defaults {
		if strings.TrimSpace(environment[name]) == "" {
			environment[name] = value
		}
	}
	return appconfig.Load(ctx, appconfig.LoadOptions{
		Landscape: landscape,
		Sources: appconfig.LoadSources{
			Base:        config.NewFileYAMLSource("base", filepath.Join(configDirectory, "settings.yaml")),
			Overlays:    overlays,
			Environment: config.NewMapEnvSource("problem-export", environment),
		},
	})
}

func processEnvironment() map[string]string {
	environment := make(map[string]string)
	for _, entry := range os.Environ() {
		key, value, found := strings.Cut(entry, "=")
		if found {
			environment[key] = value
		}
	}
	return environment
}

func fail(operation string, err error) error {
	return fmt.Errorf("%s: %w", operation, err)
}
