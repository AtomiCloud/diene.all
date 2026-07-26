package operator_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"

	apiv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/v1alpha1"
)

// Shared envtest fixtures for the whole int suite. envtest runs a real
// kube-apiserver + etcd from KUBEBUILDER_ASSETS (nix-provided, offline); it needs
// no Docker. The MinIO ledger test (ledger_minio_test.go) uses testcontainers and
// therefore Docker.
var (
	k8sClient  client.Client
	testScheme *runtime.Scheme
	restConfig *rest.Config
)

func TestMain(m *testing.M) {
	code, err := runSuite(m)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	os.Exit(code)
}

func runSuite(m *testing.M) (int, error) {
	crdDir := filepath.Join("..", "..", "..", "infra", "root_chart", "templates", "crds")
	if override := os.Getenv("CRD_DIR"); override != "" {
		crdDir = override
	}
	env := &envtest.Environment{
		CRDDirectoryPaths:     []string{crdDir},
		ErrorIfCRDPathMissing: true,
	}
	cfg, err := env.Start()
	if err != nil {
		return 0, fmt.Errorf("start envtest: %w", err)
	}
	defer func() { _ = env.Stop() }()

	scheme := runtime.NewScheme()
	if err = clientgoscheme.AddToScheme(scheme); err != nil {
		return 0, fmt.Errorf("register client-go scheme: %w", err)
	}
	if err = apiv1alpha1.AddToScheme(scheme); err != nil {
		return 0, fmt.Errorf("register sample scheme: %w", err)
	}

	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		return 0, fmt.Errorf("build client: %w", err)
	}

	k8sClient = c
	testScheme = scheme
	restConfig = cfg
	return m.Run(), nil
}
