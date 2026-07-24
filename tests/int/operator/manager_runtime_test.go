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
)

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
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address="+healthAddress,
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
