package authengine

import (
	"slices"
	"strings"
)

// Resource is one registered backend in the resource tree.
type Resource struct {
	// Name is the logical backend name consumers resolve tokens by, e.g.
	// "alcohol-zinc". It is also what derives the per-backend registration
	// claim, so it must match the backend's own service-tree identity.
	Name string
	// Indicator is the OIDC resource indicator the IdP mints a token for.
	Indicator string
	// Scopes are the scopes requested for this resource.
	Scopes []string
}

// ResourceTree is the declared set of backends a consumer holds per-resource
// access tokens for.
//
// It exists because a consumer onboards to MANY backends and each one needs its
// own token: the tree is the single declaration point, so a token cache, an
// onboarding round, and a client tree all agree on which backends exist without
// three separate lists drifting apart. A region is just another backend here —
// multi-region federation adds no new machinery.
type ResourceTree struct {
	problems *Problems
	ordered  []Resource
	index    map[string]Resource
}

// NewResourceTree declares the resource tree, rejecting a blank name or
// indicator (M33: a blank value is unset, not a resource called "") and any
// duplicate name, because a duplicate silently shadows one backend's tokens.
func NewResourceTree(problems *Problems, resources ...Resource) (ResourceTree, error) {
	if problems == nil {
		return ResourceTree{}, errUnconfigured("resource tree")
	}
	ordered := make([]Resource, 0, len(resources))
	index := make(map[string]Resource, len(resources))
	for _, resource := range resources {
		if strings.TrimSpace(resource.Name) == "" {
			return ResourceTree{}, problems.Raise(ProblemConfigInvalid,
				"a resource-tree entry carries a blank name", nil)
		}
		if strings.TrimSpace(resource.Indicator) == "" {
			return ResourceTree{}, problems.Raise(ProblemConfigInvalid,
				"a resource-tree entry carries a blank resource indicator",
				map[string]any{"name": resource.Name})
		}
		if _, duplicate := index[resource.Name]; duplicate {
			return ResourceTree{}, problems.Raise(ProblemConfigInvalid,
				"the resource tree declares one name twice",
				map[string]any{"name": resource.Name})
		}
		entry := Resource{
			Name:      resource.Name,
			Indicator: resource.Indicator,
			Scopes:    slices.Clone(resource.Scopes),
		}
		index[entry.Name] = entry
		ordered = append(ordered, entry)
	}
	return ResourceTree{problems: problems, ordered: ordered, index: index}, nil
}

// Resources returns the declared resources in declaration order.
func (t ResourceTree) Resources() []Resource {
	return slices.Clone(t.ordered)
}

// Names returns the declared resource names in declaration order.
func (t ResourceTree) Names() []string {
	names := make([]string, 0, len(t.ordered))
	for _, resource := range t.ordered {
		names = append(names, resource.Name)
	}
	return names
}

// Lookup returns the resource declared under name and whether it was present.
func (t ResourceTree) Lookup(name string) (Resource, bool) {
	resource, found := t.index[name]
	return resource, found
}

// Require returns the resource declared under name, or a problem-typed error
// naming the resources that ARE declared — an unregistered resource is a
// consumer wiring mistake, and the list is what makes it obvious.
func (t ResourceTree) Require(name string) (Resource, error) {
	resource, found := t.index[name]
	if !found {
		return Resource{}, t.problems.Raise(ProblemResourceUnregistered,
			"the resource tree declares no such resource",
			map[string]any{"resource": name, "declared": t.Names()})
	}
	return resource, nil
}
