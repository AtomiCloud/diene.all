package problem

// CatalogEndpoint is a method+path pair declaring which endpoint can return a
// problem.
type CatalogEndpoint struct {
	// Method is the HTTP method, e.g. GET, POST.
	Method string
	// Path is the absolute path, e.g. /user/me.
	Path string
}

// ToContent renders the endpoint as its Problem CR content member.
func (e CatalogEndpoint) ToContent() map[string]any {
	return map[string]any{
		"method": e.Method,
		"path":   e.Path,
	}
}

// CatalogEntry is one per-endpoint catalog entry (C0 §14 `problems[]` shape).
//
// The TypeURI is built in exactly ONE place; callers pass a URI minted by
// [TypeURI] (typically via [Registry.TypeURIFor] or
// [Catalog.AddType]) so no second template exists.
type CatalogEntry struct {
	// ID is the stable problem id.
	ID string
	// TypeURI is the RFC 9457 `type` URI built by [TypeURI].
	TypeURI string
	// Title is a short human-readable title.
	Title string
	// Status is the HTTP status code.
	Status int
	// Recoverable is the recoverable-vs-fatal flag the frontend classifier reads.
	Recoverable bool
	// DataSchema is the JSON Schema of the `data` extension payload.
	DataSchema map[string]any
	// Endpoints are the endpoints that can return this problem.
	Endpoints []CatalogEndpoint
}

// ToCRDContent renders the entry as its Problem CR content member (C0 §14):
// `{id, type, title, status, recoverable, data, endpoints[]}`.
func (e CatalogEntry) ToCRDContent() map[string]any {
	endpoints := make([]map[string]any, 0, len(e.Endpoints))
	for _, endpoint := range e.Endpoints {
		endpoints = append(endpoints, endpoint.ToContent())
	}
	data := e.DataSchema
	if data == nil {
		data = map[string]any{}
	}
	return map[string]any{
		"id":          e.ID,
		"type":        e.TypeURI,
		"title":       e.Title,
		"status":      e.Status,
		"recoverable": e.Recoverable,
		"data":        data,
		"endpoints":   endpoints,
	}
}

// Catalog is a per-service×landscape catalog of [CatalogEntry]s. It
// builds entries from a [Type] (so the type URI is always the
// single-source one) and emits the full Problem CR content payload.
type Catalog struct {
	portal  ErrorPortal
	entries map[string]CatalogEntry
	order   []string
}

// NewCatalog creates a catalog bound to portal, optionally pre-populated
// with entries.
func NewCatalog(portal ErrorPortal, entries ...CatalogEntry) *Catalog {
	catalog := &Catalog{portal: portal, entries: make(map[string]CatalogEntry, len(entries))}
	for _, entry := range entries {
		catalog.Add(entry)
	}
	return catalog
}

// Portal returns the portal used when building type URIs for entries added via
// [Catalog.AddType].
func (c *Catalog) Portal() ErrorPortal {
	return c.portal
}

// Add stores entry, replacing any existing entry with the same id while keeping
// its original insertion position.
func (c *Catalog) Add(entry CatalogEntry) {
	if _, exists := c.entries[entry.ID]; !exists {
		c.order = append(c.order, entry.ID)
	}
	c.entries[entry.ID] = entry
}

// AddType builds and adds an entry from a registry problemType, attaching
// endpoints. The type URI is minted by the single-source builder via the
// catalog's portal, so this is the canonical way to declare a cataloged
// problem. A default status of 500 is applied when the type has no status hint.
func (c *Catalog) AddType(problemType Type, endpoints ...CatalogEndpoint) error {
	typeURI, err := TypeURI(c.portal, problemType.Version, problemType.ID)
	if err != nil {
		return err
	}
	status := problemType.Status
	if status == 0 {
		status = defaultProblemStatus
	}
	if endpoints == nil {
		endpoints = []CatalogEndpoint{}
	}
	c.Add(CatalogEntry{
		ID:          problemType.ID,
		TypeURI:     typeURI,
		Title:       problemType.Title,
		Status:      status,
		Recoverable: problemType.Recoverable,
		DataSchema:  problemType.DataSchema,
		Endpoints:   endpoints,
	})
	return nil
}

// AddGenerics adds the [GenericProblems] baseline set, returning the first
// [InvalidSegmentError] encountered while building type URIs.
func (c *Catalog) AddGenerics() error {
	for _, problemType := range GenericProblems() {
		if err := c.AddType(problemType); err != nil {
			return err
		}
	}
	return nil
}

// Lookup returns the entry registered for id and whether it was present.
func (c *Catalog) Lookup(id string) (CatalogEntry, bool) {
	entry, ok := c.entries[id]
	return entry, ok
}

// Entries returns the declared entries in insertion order.
func (c *Catalog) Entries() []CatalogEntry {
	entries := make([]CatalogEntry, 0, len(c.order))
	for _, id := range c.order {
		entries = append(entries, c.entries[id])
	}
	return entries
}

// ToCRDContent emits the full Problem CR content payload (C0 §14): the
// `problems[]` list rendered per row by the service's primordial chart.
func (c *Catalog) ToCRDContent() []map[string]any {
	content := make([]map[string]any, 0, len(c.order))
	for _, id := range c.order {
		content = append(content, c.entries[id].ToCRDContent())
	}
	return content
}
