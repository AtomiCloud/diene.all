package operator_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
)

// fakeCF is a minimal in-process Cloudflare v4 API double for the HTTP adapter:
// it exercises the adapter's envelope handling, token semantics, idempotent
// tunnel/DNS/application flows, and the duplicate-create 409.
type fakeCF struct {
	mu           sync.Mutex
	tunnels      map[string]map[string]any
	apps         map[string]map[string]any
	dns          map[string]map[string]any
	policies     []map[string]any
	certHosts    []string
	failNextApp  bool
	configPushes int
	sequence     int
}

func newFakeCF() *fakeCF {
	return &fakeCF{
		tunnels: map[string]map[string]any{},
		apps:    map[string]map[string]any{},
		dns:     map[string]map[string]any{},
		policies: []map[string]any{
			{"id": "pol-1", "name": "atomi-admins"},
			{"id": "pol-2", "name": "atomi-data-owners"},
		},
		certHosts: []string{"admin.atomi.cloud", "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud"},
	}
}

func (f *fakeCF) id(prefix string) string {
	f.sequence++
	return fmt.Sprintf("%s-%d", prefix, f.sequence)
}

func write(w http.ResponseWriter, status int, success bool, result any, errs ...map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	body := map[string]any{"success": success, "errors": errs, "result": result}
	_ = json.NewEncoder(w).Encode(body)
}

func (f *fakeCF) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()

		if r.Header.Get("Authorization") != "Bearer good-token" {
			write(w, http.StatusUnauthorized, false, nil, map[string]any{"code": 10000, "message": "Invalid API Token"})
			return
		}

		path := r.URL.Path
		switch {
		case path == "/user/tokens/verify":
			write(w, http.StatusOK, true, map[string]any{"status": "active"})
		case strings.HasSuffix(path, "/cfd_tunnel") && r.Method == http.MethodGet:
			name := r.URL.Query().Get("name")
			var out []map[string]any
			if tunnel, ok := f.tunnels[name]; ok {
				out = append(out, tunnel)
			}
			write(w, http.StatusOK, true, out)
		case strings.HasSuffix(path, "/cfd_tunnel") && r.Method == http.MethodPost:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			name, _ := body["name"].(string) //nolint:revive // fake test double; missing name is a test bug surfaced by assertions
			tunnel := map[string]any{"id": f.id("tun"), "name": name, "token": "tunnel-token-" + name}
			f.tunnels[name] = tunnel
			write(w, http.StatusOK, true, tunnel)
		case strings.HasSuffix(path, "/token") && r.Method == http.MethodGet:
			write(w, http.StatusOK, true, "looked-up-token")
		case strings.HasSuffix(path, "/configurations") && r.Method == http.MethodPut:
			f.configPushes++
			write(w, http.StatusOK, true, map[string]any{"version": f.configPushes})
		case path == "/zones" && r.Method == http.MethodGet:
			name := r.URL.Query().Get("name")
			if name == "admin.atomi.cloud" {
				write(w, http.StatusOK, true, []map[string]any{{"id": "zone-1", "name": name}})
				return
			}
			write(w, http.StatusOK, true, []map[string]any{})
		case strings.Contains(path, "/ssl/certificate_packs"):
			write(w, http.StatusOK, true, []map[string]any{{"status": "active", "hosts": f.certHosts}})
		case strings.HasSuffix(path, "/access/policies"):
			write(w, http.StatusOK, true, f.policies)
		case strings.HasSuffix(path, "/access/apps") && r.Method == http.MethodGet:
			var out []map[string]any
			for _, app := range f.apps {
				out = append(out, app)
			}
			write(w, http.StatusOK, true, out)
		case strings.HasSuffix(path, "/access/apps") && r.Method == http.MethodPost:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			domain, _ := body["domain"].(string) //nolint:revive // fake test double
			if _, exists := f.apps[domain]; exists || f.failNextApp {
				f.failNextApp = false
				if _, exists := f.apps[domain]; !exists {
					body["id"] = f.id("app")
					f.apps[domain] = body
				}
				write(w, http.StatusConflict, false, nil,
					map[string]any{"code": 12130, "message": "access.api.error.application_already_exists"})
				return
			}
			body["id"] = f.id("app")
			f.apps[domain] = body
			write(w, http.StatusCreated, true, body)
		case strings.Contains(path, "/access/apps/") && r.Method == http.MethodPut:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			domain, _ := body["domain"].(string) //nolint:revive // fake test double
			id := path[strings.LastIndex(path, "/")+1:]
			body["id"] = id
			f.apps[domain] = body
			write(w, http.StatusOK, true, body)
		case strings.Contains(path, "/access/apps/") && r.Method == http.MethodDelete:
			id := path[strings.LastIndex(path, "/")+1:]
			for domain, app := range f.apps {
				if app["id"] == id {
					delete(f.apps, domain)
				}
			}
			write(w, http.StatusOK, true, map[string]any{"id": id})
		case strings.HasSuffix(path, "/dns_records") && r.Method == http.MethodGet:
			name := r.URL.Query().Get("name")
			var out []map[string]any
			if record, ok := f.dns[name]; ok {
				out = append(out, record)
			}
			write(w, http.StatusOK, true, out)
		case strings.HasSuffix(path, "/dns_records") && r.Method == http.MethodPost:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			name, _ := body["name"].(string) //nolint:revive // fake test double; missing name is a test bug surfaced by assertions
			body["id"] = f.id("rec")
			f.dns[name] = body
			write(w, http.StatusOK, true, body)
		case strings.Contains(path, "/dns_records/") && r.Method == http.MethodPut:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			name, _ := body["name"].(string) //nolint:revive // fake test double; missing name is a test bug surfaced by assertions
			body["id"] = path[strings.LastIndex(path, "/")+1:]
			f.dns[name] = body
			write(w, http.StatusOK, true, body)
		case strings.Contains(path, "/dns_records/") && r.Method == http.MethodDelete:
			id := path[strings.LastIndex(path, "/")+1:]
			for name, record := range f.dns {
				if record["id"] == id {
					delete(f.dns, name)
				}
			}
			write(w, http.StatusOK, true, map[string]any{"id": id})
		default:
			write(w, http.StatusNotFound, false, nil, map[string]any{"code": 7000, "message": "not found: " + path})
		}
	})
}

func newHTTPAdapter(t *testing.T) (*cloudflare.HTTP, *fakeCF) {
	t.Helper()
	fake := newFakeCF()
	server := httptest.NewServer(fake.handler())
	t.Cleanup(server.Close)
	adapter := cloudflare.NewHTTP()
	adapter.BaseURL = server.URL
	return adapter, fake
}

var goodCredentials = cloudflare.Credentials{AccountID: "acc-1", APIToken: "good-token"}

func TestHTTPValidateToken(t *testing.T) {
	adapter, _ := newHTTPAdapter(t)
	require.NoError(t, adapter.ValidateToken(context.Background(), goodCredentials))

	err := adapter.ValidateToken(context.Background(), cloudflare.Credentials{AccountID: "acc-1", APIToken: "bad"})
	require.ErrorIs(t, err, cloudflare.ErrInvalidToken)
}

func TestHTTPEnsureTunnelIdempotentOnce(t *testing.T) {
	adapter, fake := newHTTPAdapter(t)

	created, err := adapter.EnsureTunnel(context.Background(), goodCredentials, "admin", "admin.atomi.cloud")
	require.NoError(t, err)
	require.NotEmpty(t, created.ID)
	require.Equal(t, created.ID+".cfargotunnel.com", created.CNAME)
	require.Equal(t, "tunnel-token-admin", created.Token)

	// A second ensure adopts the existing tunnel (token via lookup, not create).
	adopted, err := adapter.EnsureTunnel(context.Background(), goodCredentials, "admin", "admin.atomi.cloud")
	require.NoError(t, err)
	require.Equal(t, created.ID, adopted.ID)
	require.Equal(t, "looked-up-token", adopted.Token)
	require.Len(t, fake.tunnels, 1)
}

func TestHTTPPushTunnelConfig(t *testing.T) {
	adapter, fake := newHTTPAdapter(t)
	require.NoError(t, adapter.PushTunnelConfig(context.Background(), goodCredentials, "tun-1", []cloudflare.IngressRule{
		{Hostname: "a.example", Path: "/*", Backend: "http://svc:80"},
		{Hostname: "b.example", Path: "/api/*", Backend: "http://svc2:80"},
	}))
	require.Equal(t, 1, fake.configPushes)
}

func TestHTTPCheckTLSCoverageExactHostOnly(t *testing.T) {
	adapter, _ := newHTTPAdapter(t)

	covered, err := adapter.CheckTLSCoverage(context.Background(), goodCredentials,
		"admin.atomi.cloud", "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud")
	require.NoError(t, err)
	require.True(t, covered.Covered)

	// A deeper hostname not in the cert pack fails closed — universal SSL /
	// one-label wildcards are never assumed to cover the canonical dotted form.
	uncovered, err := adapter.CheckTLSCoverage(context.Background(), goodCredentials,
		"admin.atomi.cloud", "other.oxygen.nitroso.kirin.lapras.admin.atomi.cloud")
	require.NoError(t, err)
	require.False(t, uncovered.Covered)
	require.Contains(t, uncovered.Message, "no active certificate pack")

	missingZone, err := adapter.CheckTLSCoverage(context.Background(), goodCredentials,
		"unknown.zone", "a.unknown.zone")
	require.NoError(t, err)
	require.False(t, missingZone.Covered)
	require.Contains(t, missingZone.Message, "not found")
}

func TestHTTPLookupPoliciesByNameOnly(t *testing.T) {
	adapter, _ := newHTTPAdapter(t)
	resolved, err := adapter.LookupPolicies(context.Background(), goodCredentials,
		[]string{"atomi-admins", "absent-policy"})
	require.NoError(t, err)
	require.Equal(t, map[string]string{"atomi-admins": "pol-1"}, resolved)
}

func TestHTTPAccessApplicationListThenAdoptAndConflictFallback(t *testing.T) {
	adapter, fake := newHTTPAdapter(t)
	desired := cloudflare.AccessApplication{
		Name: "nitroso-viewer", Hostname: "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud",
		Path: "/*", PolicyIDs: []string{"pol-1"},
	}

	_, found, err := adapter.FindAccessApplication(context.Background(), goodCredentials, desired.Hostname, desired.Path)
	require.NoError(t, err)
	require.False(t, found)

	id, err := adapter.CreateAccessApplication(context.Background(), goodCredentials, desired)
	require.NoError(t, err)
	require.NotEmpty(t, id)

	// LIST finds it afterwards; update converges the policy set.
	foundID, found, err := adapter.FindAccessApplication(context.Background(), goodCredentials, desired.Hostname, desired.Path)
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, id, foundID)
	desired.PolicyIDs = []string{"pol-1", "pol-2"}
	require.NoError(t, adapter.UpdateAccessApplication(context.Background(), goodCredentials, id, desired))

	// The duplicate-create race 409s with the CF error string.
	fake.failNextApp = true
	other := desired
	other.Hostname = "editor.oxygen.nitroso.kirin.lapras.admin.atomi.cloud"
	_, err = adapter.CreateAccessApplication(context.Background(), goodCredentials, other)
	require.ErrorIs(t, err, cloudflare.ErrApplicationAlreadyExists)

	require.NoError(t, adapter.DeleteAccessApplication(context.Background(), goodCredentials, id))
	_, found, err = adapter.FindAccessApplication(context.Background(), goodCredentials, desired.Hostname, desired.Path)
	require.NoError(t, err)
	require.False(t, found)
}

func TestHTTPUpsertAndDeleteProxiedCNAME(t *testing.T) {
	adapter, fake := newHTTPAdapter(t)
	hostname := "viewer.oxygen.nitroso.kirin.lapras.admin.atomi.cloud"

	require.NoError(t, adapter.UpsertProxiedCNAME(context.Background(), goodCredentials,
		"admin.atomi.cloud", hostname, "tun-1.cfargotunnel.com"))
	require.Contains(t, fake.dns, hostname)

	// Upsert over an existing record updates rather than duplicates.
	require.NoError(t, adapter.UpsertProxiedCNAME(context.Background(), goodCredentials,
		"admin.atomi.cloud", hostname, "tun-2.cfargotunnel.com"))
	require.Len(t, fake.dns, 1)
	require.Equal(t, "tun-2.cfargotunnel.com", fake.dns[hostname]["content"])

	require.NoError(t, adapter.DeleteDNSRecord(context.Background(), goodCredentials, "admin.atomi.cloud", hostname))
	require.Empty(t, fake.dns)

	// Deleting under an unknown zone is a no-op, not an error.
	require.NoError(t, adapter.DeleteDNSRecord(context.Background(), goodCredentials, "unknown.zone", hostname))

	// Upserting under an unknown zone is a hard error (nothing to program).
	require.Error(t, adapter.UpsertProxiedCNAME(context.Background(), goodCredentials,
		"unknown.zone", hostname, "tun-1.cfargotunnel.com"))
}
