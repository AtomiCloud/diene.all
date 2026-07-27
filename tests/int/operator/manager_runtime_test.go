package operator_test

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"

	"github.com/AtomiCloud/diene.fleet-operator/internal/operatorruntime"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/brake"
)

func TestManagerRuntimeConfigAndCredentialParsing(t *testing.T) {
	t.Parallel()

	environment := map[string]string{
		"FLEET_OPERATOR_CLUSTER_PROVIDER_API":         "cluster",
		"FLEET_OPERATOR_PLATFORM_INFISICAL_ADMIN":     "infisical",
		"FLEET_OPERATOR_PLATFORM_GITHUB_ORG_READ":     "github",
		"FLEET_OPERATOR_PLATFORM_FLEET_REPO_WRITE":    "fleet-repo",
		"FLEET_OPERATOR_DEPENDENCY_VENDOR_ENGINE":     "vendors",
		"FLEET_OPERATOR_DEPENDENCY_BROKER_TOKEN":      "broker",
		"FLEET_OPERATOR_DEPENDENCY_NATIVE_TIGRIS_KEY": "tigris",
		"FLEET_OPERATOR_DEPENDENCY_READ_ONLY_SEED":    "mounted",
		"FLEET_OPERATOR_TRAFFIC_ROUTE53":              "route53",
		"FLEET_OPERATOR_TRAFFIC_CLOUDFLARE_DNS":       "cloudflare-dns",
		"FLEET_OPERATOR_TRAFFIC_EDGE_PUBLISHER":       "publisher",
		"FLEET_OPERATOR_WEBHOOK_MERCURY_MANAGEMENT":   "management",
		"FLEET_OPERATOR_WEBHOOK_LANDSCAPE_MERCURY_KV": "landscape-kv",
		"FLEET_OPERATOR_CF_DEPLOY_CLOUDFLARE_WORKERS": "workers",
		"FLEET_OPERATOR_INFISICAL_WRITE":              "broad-write",
		"FLEET_OPERATOR_T4_ROOT_PATH":                 "root-path",
	}
	getenv := func(name string) string { return environment[name] }

	config := operatorruntime.DefaultConfig(getenv)
	require.True(t, config.EnableNote)
	require.True(t, config.EnableJournal)
	require.False(t, config.EnableCluster)
	require.False(t, config.EnablePlatform)
	require.False(t, config.EnableDependency)
	require.False(t, config.EnableTraffic)
	require.False(t, config.EnableWebhook)
	require.False(t, config.EnableCfDeploy)
	require.False(t, config.EnableProblem)
	require.Equal(t, brake.DefaultTrafficCapPercent, config.TrafficCapPercent)
	require.Equal(t, brake.DefaultDependencyCapPerTick, config.DependencyDestructiveCapPerTick)
	require.Equal(t, 20, config.BlastBrakeCap)

	credentials := operatorruntime.CredentialSetFromEnvironment(getenv)
	require.Equal(t, "cluster", credentials.Cluster.ProviderAPI)
	require.Equal(t, "infisical", credentials.Platform.InfisicalAdmin)
	require.Equal(t, "github", credentials.Platform.GitHubOrgRead)
	require.Equal(t, "fleet-repo", credentials.Platform.FleetRepoWrite)
	require.Equal(t, "vendors", credentials.Dependency.VendorEngine)
	require.Equal(t, "broker", credentials.Dependency.BrokerToken)
	require.Equal(t, "tigris", credentials.Dependency.NativeTigrisKey)
	require.True(t, credentials.Dependency.ReadOnlySeed)
	require.Equal(t, "route53", credentials.Traffic.Route53)
	require.Equal(t, "cloudflare-dns", credentials.Traffic.CloudflareDNS)
	require.Equal(t, "publisher", credentials.Traffic.EdgePublisher)
	require.Equal(t, "management", credentials.Webhook.MercuryManagement)
	require.Equal(t, "landscape-kv", credentials.Webhook.LandscapeMercuryKV)
	require.Equal(t, "workers", credentials.CfDeploy.CloudflareWorkers)
	require.Equal(t, "broad-write", credentials.InfisicalWrite)
	require.Equal(t, "root-path", credentials.T4RootPath)

	empty := operatorruntime.CredentialSetFromEnvironment(func(string) string { return "   " })
	require.False(t, empty.Dependency.ReadOnlySeed)
}

func TestManagerRuntimeHealthEndpoints(t *testing.T) {
	binary := os.Getenv("MANAGER_BINARY")
	if binary == "" {
		t.Skip("MANAGER_BINARY is set by the manager-runtime smoke")
	}
	binary, err := filepath.Abs(binary)
	require.NoError(t, err)
	require.NoError(t, executableFile(binary))

	healthAddress := availableAddress(t)
	kubeconfig := writeEnvtestKubeconfig(t)
	//nolint:gosec // The test resolves and validates the configured manager binary before execution.
	command := exec.CommandContext(
		t.Context(),
		binary,
		"--enable-note=false",
		"--enable-journal=false",
		"--enable-cluster=false",
		"--enable-platform=false",
		"--enable-dependency=false",
		"--enable-traffic=false",
		"--enable-webhook=false",
		"--enable-cf-deploy=false",
		"--enable-problem=false",
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address="+healthAddress,
		"--traffic-cap-percent=20",
		"--dependency-destructive-cap-per-tick=3",
	)
	command.Env = append(os.Environ(), "KUBECONFIG="+kubeconfig)
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = &output
	require.NoError(t, command.Start())

	done := make(chan error, 1)
	go func() {
		done <- command.Wait()
	}()
	defer func() {
		if command.ProcessState == nil {
			_ = command.Process.Kill()
			<-done
		}
	}()

	for _, endpoint := range []string{"healthz", "readyz"} {
		url := "http://" + healthAddress + "/" + endpoint
		if !waitForOK(t.Context(), url, 10*time.Second) {
			_ = stopRuntime(command, done)
			t.Fatalf("manager endpoint %s did not answer ok\n%s", url, output.String())
		}
	}
	require.NoError(t, stopRuntime(command, done), output.String())
}

func TestManagerRuntimeProblemReservedSeam(t *testing.T) {
	binary := os.Getenv("MANAGER_BINARY")
	if binary == "" {
		t.Skip("MANAGER_BINARY is set by the manager-runtime smoke")
	}
	binary, err := filepath.Abs(binary)
	require.NoError(t, err)
	require.NoError(t, executableFile(binary))

	kubeconfig := writeEnvtestKubeconfig(t)
	//nolint:gosec // The test resolves and validates the configured manager binary before execution.
	command := exec.CommandContext(
		t.Context(),
		binary,
		"--enable-note=false",
		"--enable-journal=false",
		"--enable-problem=true",
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address=0",
	)
	command.Env = append(os.Environ(), "KUBECONFIG="+kubeconfig)
	output, err := command.CombinedOutput()
	require.Error(t, err)
	var exitError *exec.ExitError
	require.ErrorAs(t, err, &exitError)
	require.Equal(t, 1, exitError.ExitCode())
	require.Contains(t, string(output), "problem sub-component not yet folded")
}

func executableFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0 {
		return nil
	}
	return errors.New("manager binary is not executable")
}

func availableAddress(t *testing.T) string {
	t.Helper()
	var listenConfig net.ListenConfig
	listener, err := listenConfig.Listen(t.Context(), "tcp", "127.0.0.1:0")
	require.NoError(t, err)
	address := listener.Addr().String()
	require.NoError(t, listener.Close())
	return address
}

func writeEnvtestKubeconfig(t *testing.T) string {
	t.Helper()
	data, err := clientcmd.Write(clientcmdapi.Config{
		Clusters: map[string]*clientcmdapi.Cluster{
			"envtest": {
				Server:                   restConfig.Host,
				CertificateAuthorityData: restConfig.CAData,
				InsecureSkipTLSVerify:    restConfig.Insecure,
			},
		},
		AuthInfos: map[string]*clientcmdapi.AuthInfo{
			"envtest": {
				ClientCertificateData: restConfig.CertData,
				ClientKeyData:         restConfig.KeyData,
				Token:                 restConfig.BearerToken,
				Username:              restConfig.Username,
				Password:              restConfig.Password,
			},
		},
		Contexts: map[string]*clientcmdapi.Context{
			"envtest": {Cluster: "envtest", AuthInfo: "envtest"},
		},
		CurrentContext: "envtest",
	})
	require.NoError(t, err)
	path := filepath.Join(t.TempDir(), "kubeconfig")
	require.NoError(t, os.WriteFile(path, data, 0o600))
	return path
}

func waitForOK(ctx context.Context, url string, timeout time.Duration) bool {
	client := &http.Client{Timeout: 500 * time.Millisecond}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
		if err != nil {
			return false
		}
		response, err := client.Do(request)
		if err == nil {
			body, readErr := io.ReadAll(response.Body)
			closeErr := response.Body.Close()
			if readErr == nil && closeErr == nil && response.StatusCode == http.StatusOK && strings.TrimSpace(string(body)) == "ok" {
				return true
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
}

func stopRuntime(command *exec.Cmd, done <-chan error) error {
	signalErr := command.Process.Signal(os.Interrupt)
	select {
	case waitErr := <-done:
		if signalErr != nil && !errors.Is(signalErr, os.ErrProcessDone) {
			return signalErr
		}
		return waitErr
	case <-time.After(5 * time.Second):
		_ = command.Process.Kill()
		<-done
		return errors.New("manager did not stop after interrupt")
	}
}
