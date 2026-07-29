package apiengine

import (
	"net/http"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
)

// TreeOptions configures a [ClientTree].
type TreeOptions struct {
	// Config is the engine's owned config block, already merged and validated
	// by the consumer's config lib.
	Config Config
	// Doer is the outbound HTTP seam shared by every backend's client.
	// Defaults to [http.DefaultClient].
	Doer Doer
	// Tokens resolves credentials per backend.
	//
	// This is the auth-engine seam: a *authengine.TokenCache satisfies it, and
	// [authengine.NewClientCredentialsSource] behind that cache covers the
	// operator machine-to-machine flow. One retriever serves every backend
	// because it resolves BY resource name, which is precisely the per-backend
	// resolution this tree needs.
	Tokens authengine.Retriever
	// Problems mints the engine's problem-typed errors. Required.
	Problems *Problems
	// Sleep waits before a retry. Defaults to [time.Sleep].
	Sleep func(time.Duration)
}

// ClientTree is the multi-backend client registry.
//
// One consumer onboards to MANY backends, and each needs its own origin and its
// own token. The tree is the single place that mapping lives, so the config
// block, the auth-engine resource tree, and the clients a caller resolves can
// never drift into three disagreeing lists. Registering a region is registering
// a backend — there is no separate region concept, because routing between
// regions belongs to the DNS gray zone (ARCHITECTURE §4).
type ClientTree struct {
	names    []string
	clients  map[string]*Client
	problems *Problems
}

// NewClientTree builds one client per configured backend.
//
// The configuration is validated first, so a tree either exists complete or not
// at all: a consumer never discovers a malformed backend on its first call in
// production.
func NewClientTree(options TreeOptions) (*ClientTree, error) {
	if options.Problems == nil {
		return nil, errUnconfigured("client tree")
	}
	if err := options.Config.Validate(options.Problems); err != nil {
		return nil, err
	}

	doer := options.Doer
	if doer == nil {
		doer = http.DefaultClient
	}

	names := options.Config.Names()
	clients := make(map[string]*Client, len(names))
	for _, name := range names {
		client, err := NewClient(ClientOptions{
			Backend:  name,
			Config:   options.Config.Backends[name],
			Doer:     doer,
			Tokens:   options.Tokens,
			Resource: options.Config.Resource(name),
			Problems: options.Problems,
			Retry:    options.Config.Retry,
			Sleep:    options.Sleep,
		})
		if err != nil {
			return nil, err
		}
		clients[name] = client
	}
	return &ClientTree{names: names, clients: clients, problems: options.Problems}, nil
}

// Names returns the registered backend names in stable (sorted) order.
func (t *ClientTree) Names() []string {
	out := make([]string, len(t.names))
	copy(out, t.names)
	return out
}

// Backend returns the named backend's client.
//
// An unregistered name is a problem-typed error rather than a nil client,
// because calling a backend nobody registered is a configuration mistake the
// consumer needs told about, not a nil dereference at the call site.
func (t *ClientTree) Backend(name string) (*Client, error) {
	client, found := t.clients[name]
	if !found {
		return nil, t.problems.Raise(ProblemBackendUnregistered,
			"no backend is registered as "+name,
			map[string]any{"backend": name, "registered": t.Names()})
	}
	return client, nil
}

// Problems returns the factory this tree and its clients mint errors through,
// for a consumer composing one catalog across every engine it uses.
func (t *ClientTree) Problems() *Problems { return t.problems }
