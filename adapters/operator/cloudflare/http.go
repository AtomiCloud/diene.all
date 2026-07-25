package cloudflare

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// DefaultBaseURL is the Cloudflare v4 API root.
const DefaultBaseURL = "https://api.cloudflare.com/client/v4"

// HTTP implements Port over the real Cloudflare v4 API.
type HTTP struct {
	BaseURL string
	Client  *http.Client
}

// NewHTTP constructs the production Cloudflare adapter.
func NewHTTP() *HTTP {
	return &HTTP{BaseURL: DefaultBaseURL, Client: &http.Client{Timeout: 30 * time.Second}}
}

type envelope struct {
	Success bool            `json:"success"`
	Errors  []apiError      `json:"errors"`
	Result  json.RawMessage `json:"result"`
}

type apiError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (h *HTTP) do(ctx context.Context, credentials Credentials, method, path string, body any, out any) error {
	var payload io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode %s %s: %w", method, path, err)
		}
		payload = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(ctx, method, h.BaseURL+path, payload)
	if err != nil {
		return fmt.Errorf("build %s %s: %w", method, path, err)
	}
	request.Header.Set("Authorization", "Bearer "+credentials.APIToken)
	request.Header.Set("Content-Type", "application/json")

	response, err := h.Client.Do(request)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer func() { _ = response.Body.Close() }()

	raw, err := io.ReadAll(response.Body)
	if err != nil {
		return fmt.Errorf("read %s %s: %w", method, path, err)
	}
	var env envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		return fmt.Errorf("decode %s %s (status %d): %w", method, path, response.StatusCode, err)
	}
	if !env.Success {
		for _, e := range env.Errors {
			if strings.Contains(e.Message, "application_already_exists") {
				return ErrApplicationAlreadyExists
			}
		}
		if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
			return ErrInvalidToken
		}
		return fmt.Errorf("%s %s: cloudflare error (status %d): %v", method, path, response.StatusCode, env.Errors)
	}
	if out != nil && len(env.Result) > 0 {
		if err := json.Unmarshal(env.Result, out); err != nil {
			return fmt.Errorf("decode result %s %s: %w", method, path, err)
		}
	}
	return nil
}

// ValidateToken verifies the token against the token-verify endpoint.
func (h *HTTP) ValidateToken(ctx context.Context, credentials Credentials) error {
	return h.do(ctx, credentials, http.MethodGet, "/user/tokens/verify", nil, nil)
}

type tunnelResult struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Token string `json:"token"`
}

// EnsureTunnel finds the named tunnel or creates it (idempotent-once,
// lookup-first per the family find-or-adopt convention).
func (h *HTTP) EnsureTunnel(ctx context.Context, credentials Credentials, name, _ string) (Tunnel, error) {
	var existing []tunnelResult
	listPath := fmt.Sprintf("/accounts/%s/cfd_tunnel?name=%s&is_deleted=false", credentials.AccountID, url.QueryEscape(name))
	if err := h.do(ctx, credentials, http.MethodGet, listPath, nil, &existing); err != nil {
		return Tunnel{}, err
	}
	if len(existing) > 0 {
		t := existing[0]
		token, err := h.tunnelToken(ctx, credentials, t.ID)
		if err != nil {
			return Tunnel{}, err
		}
		return Tunnel{ID: t.ID, Name: t.Name, CNAME: t.ID + ".cfargotunnel.com", Token: token}, nil
	}

	var created tunnelResult
	createPath := fmt.Sprintf("/accounts/%s/cfd_tunnel", credentials.AccountID)
	body := map[string]any{"name": name, "config_src": "cloudflare"}
	if err := h.do(ctx, credentials, http.MethodPost, createPath, body, &created); err != nil {
		return Tunnel{}, err
	}
	token := created.Token
	if token == "" {
		var err error
		token, err = h.tunnelToken(ctx, credentials, created.ID)
		if err != nil {
			return Tunnel{}, err
		}
	}
	return Tunnel{ID: created.ID, Name: created.Name, CNAME: created.ID + ".cfargotunnel.com", Token: token}, nil
}

func (h *HTTP) tunnelToken(ctx context.Context, credentials Credentials, tunnelID string) (string, error) {
	var token string
	path := fmt.Sprintf("/accounts/%s/cfd_tunnel/%s/token", credentials.AccountID, tunnelID)
	if err := h.do(ctx, credentials, http.MethodGet, path, nil, &token); err != nil {
		return "", err
	}
	return token, nil
}

// PushTunnelConfig PUTs the versioned remote ingress configuration; running
// cloudflared replicas long-poll and hot-reload it (no restart, no ConfigMap).
func (h *HTTP) PushTunnelConfig(ctx context.Context, credentials Credentials, tunnelID string, rules []IngressRule) error {
	ingress := make([]map[string]any, 0, len(rules)+1)
	for _, rule := range rules {
		entry := map[string]any{"hostname": rule.Hostname, "service": rule.Backend}
		if rule.Path != "" && rule.Path != "/*" {
			entry["path"] = strings.TrimSuffix(strings.TrimPrefix(rule.Path, "/"), "/*")
		}
		ingress = append(ingress, entry)
	}
	ingress = append(ingress, map[string]any{"service": "http_status:404"})
	path := fmt.Sprintf("/accounts/%s/cfd_tunnel/%s/configurations", credentials.AccountID, tunnelID)
	return h.do(ctx, credentials, http.MethodPut, path, map[string]any{"config": map[string]any{"ingress": ingress}}, nil)
}

type zoneResult struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type certificatePack struct {
	Hosts  []string `json:"hosts"`
	Status string   `json:"status"`
}

// CheckTLSCoverage preflights exact multi-label DNS/edge-TLS coverage: the zone
// must exist and an active certificate pack must cover the exact hostname (a
// one-label wildcard never covers the deeper canonical dotted form). Fails
// closed on any gap.
func (h *HTTP) CheckTLSCoverage(ctx context.Context, credentials Credentials, zone, hostname string) (TLSCoverage, error) {
	zoneID, err := h.zoneID(ctx, credentials, zone)
	if err != nil {
		return TLSCoverage{}, err
	}
	if zoneID == "" {
		return TLSCoverage{Message: fmt.Sprintf("zone %q not found in account", zone)}, nil
	}
	var packs []certificatePack
	path := fmt.Sprintf("/zones/%s/ssl/certificate_packs?status=all", zoneID)
	if err := h.do(ctx, credentials, http.MethodGet, path, nil, &packs); err != nil {
		return TLSCoverage{}, err
	}
	for _, pack := range packs {
		if pack.Status != "active" {
			continue
		}
		for _, host := range pack.Hosts {
			if hostCovers(host, hostname) {
				return TLSCoverage{Covered: true}, nil
			}
		}
	}
	return TLSCoverage{Message: fmt.Sprintf("no active certificate pack covers %q exactly (universal/wildcard coverage is never assumed)", hostname)}, nil
}

// hostCovers reports whether a certificate host entry covers hostname exactly:
// a literal match, or a wildcard whose remainder is exactly one label.
func hostCovers(host, hostname string) bool {
	if host == hostname {
		return true
	}
	if rest, ok := strings.CutPrefix(host, "*."); ok {
		remainder, matches := strings.CutSuffix(hostname, "."+rest)
		return matches && remainder != "" && !strings.Contains(remainder, ".")
	}
	return false
}

func (h *HTTP) zoneID(ctx context.Context, credentials Credentials, zone string) (string, error) {
	var zones []zoneResult
	path := "/zones?name=" + url.QueryEscape(zone)
	if err := h.do(ctx, credentials, http.MethodGet, path, nil, &zones); err != nil {
		return "", err
	}
	if len(zones) == 0 {
		return "", nil
	}
	return zones[0].ID, nil
}

type policyResult struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// LookupPolicies resolves each policy NAME to its reusable Access policy id.
// This operator never authors a policy; a missing name is absent from the map.
func (h *HTTP) LookupPolicies(ctx context.Context, credentials Credentials, names []string) (map[string]string, error) {
	var policies []policyResult
	path := fmt.Sprintf("/accounts/%s/access/policies", credentials.AccountID)
	if err := h.do(ctx, credentials, http.MethodGet, path, nil, &policies); err != nil {
		return nil, err
	}
	byName := make(map[string]string, len(policies))
	for _, p := range policies {
		byName[p.Name] = p.ID
	}
	resolved := make(map[string]string, len(names))
	for _, name := range names {
		if id, ok := byName[name]; ok {
			resolved[name] = id
		}
	}
	return resolved, nil
}

type accessAppResult struct {
	ID     string `json:"id"`
	Domain string `json:"domain"`
}

func accessDomain(hostname, path string) string {
	if path == "" || path == "/*" {
		return hostname
	}
	return hostname + strings.TrimSuffix(path, "/*")
}

// FindAccessApplication LISTs applications and matches on the exact domain.
func (h *HTTP) FindAccessApplication(ctx context.Context, credentials Credentials, hostname, path string) (string, bool, error) {
	var apps []accessAppResult
	listPath := fmt.Sprintf("/accounts/%s/access/apps", credentials.AccountID)
	if err := h.do(ctx, credentials, http.MethodGet, listPath, nil, &apps); err != nil {
		return "", false, err
	}
	wanted := accessDomain(hostname, path)
	for _, app := range apps {
		if app.Domain == wanted {
			return app.ID, true, nil
		}
	}
	return "", false, nil
}

func accessAppBody(desired AccessApplication) map[string]any {
	return map[string]any{
		"name":     desired.Name,
		"domain":   accessDomain(desired.Hostname, desired.Path),
		"type":     "self_hosted",
		"policies": desired.PolicyIDs,
	}
}

// CreateAccessApplication creates the application; a duplicate-create race
// surfaces as ErrApplicationAlreadyExists for the LIST-then-adopt fallback.
func (h *HTTP) CreateAccessApplication(ctx context.Context, credentials Credentials, desired AccessApplication) (string, error) {
	var created accessAppResult
	path := fmt.Sprintf("/accounts/%s/access/apps", credentials.AccountID)
	if err := h.do(ctx, credentials, http.MethodPost, path, accessAppBody(desired), &created); err != nil {
		return "", err
	}
	return created.ID, nil
}

// UpdateAccessApplication converges an existing application to desired
// (policies attached in the exact array order — CF-native evaluation order).
func (h *HTTP) UpdateAccessApplication(ctx context.Context, credentials Credentials, id string, desired AccessApplication) error {
	path := fmt.Sprintf("/accounts/%s/access/apps/%s", credentials.AccountID, id)
	return h.do(ctx, credentials, http.MethodPut, path, accessAppBody(desired), nil)
}

type dnsRecord struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Content string `json:"content"`
}

// UpsertProxiedCNAME programs the one proxied CNAME for the complete dotted
// hostname to <tunnelID>.cfargotunnel.com.
func (h *HTTP) UpsertProxiedCNAME(ctx context.Context, credentials Credentials, zone, hostname, target string) error {
	zoneID, err := h.zoneID(ctx, credentials, zone)
	if err != nil {
		return err
	}
	if zoneID == "" {
		return fmt.Errorf("zone %q not found in account", zone)
	}
	var records []dnsRecord
	listPath := fmt.Sprintf("/zones/%s/dns_records?type=CNAME&name=%s", zoneID, url.QueryEscape(hostname))
	if err := h.do(ctx, credentials, http.MethodGet, listPath, nil, &records); err != nil {
		return err
	}
	body := map[string]any{"type": "CNAME", "name": hostname, "content": target, "proxied": true, "ttl": 1}
	if len(records) > 0 {
		path := fmt.Sprintf("/zones/%s/dns_records/%s", zoneID, records[0].ID)
		return h.do(ctx, credentials, http.MethodPut, path, body, nil)
	}
	path := fmt.Sprintf("/zones/%s/dns_records", zoneID)
	return h.do(ctx, credentials, http.MethodPost, path, body, nil)
}

// DeleteAccessApplication removes an application by id.
func (h *HTTP) DeleteAccessApplication(ctx context.Context, credentials Credentials, id string) error {
	path := fmt.Sprintf("/accounts/%s/access/apps/%s", credentials.AccountID, id)
	return h.do(ctx, credentials, http.MethodDelete, path, nil, nil)
}

// DeleteDNSRecord removes the proxied CNAME for hostname.
func (h *HTTP) DeleteDNSRecord(ctx context.Context, credentials Credentials, zone, hostname string) error {
	zoneID, err := h.zoneID(ctx, credentials, zone)
	if err != nil {
		return err
	}
	if zoneID == "" {
		return nil
	}
	var records []dnsRecord
	listPath := fmt.Sprintf("/zones/%s/dns_records?type=CNAME&name=%s", zoneID, url.QueryEscape(hostname))
	if err := h.do(ctx, credentials, http.MethodGet, listPath, nil, &records); err != nil {
		return err
	}
	for _, record := range records {
		path := fmt.Sprintf("/zones/%s/dns_records/%s", zoneID, record.ID)
		if err := h.do(ctx, credentials, http.MethodDelete, path, nil, nil); err != nil {
			return err
		}
	}
	return nil
}
