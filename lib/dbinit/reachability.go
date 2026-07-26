// Package dbinit implements dependency reachability, migration, and
// idempotent-seed orchestration for the one-shot db-init command.
package dbinit

import (
	"context"
	"fmt"
	"strings"
)

// Probe is one dependency reachability check.
type Probe interface {
	Ping(ctx context.Context) error
}

// NamedProbe associates a configured connection name with its probe.
type NamedProbe struct {
	Name  string
	Probe Probe
}

// ReachabilityOptions groups checks by dependency kind in execution order.
type ReachabilityOptions struct {
	Postgres []NamedProbe
	Redis    []NamedProbe
	Storage  []NamedProbe
}

// ReachabilityChecks executes the db-init dependency matrix.
type ReachabilityChecks struct {
	postgres []NamedProbe
	redis    []NamedProbe
	storage  []NamedProbe
}

// ValidateProbes validates one configured dependency group.
func ValidateProbes(kind string, probes []NamedProbe) error {
	for index, probe := range probes {
		if strings.TrimSpace(probe.Name) == "" {
			return fmt.Errorf("dbinit: %s probe %d has no name", kind, index)
		}
		if probe.Probe == nil {
			return fmt.Errorf("dbinit: %s probe %q is required", kind, probe.Name)
		}
	}
	return nil
}

// NewReachabilityChecks creates the ordered reachability matrix.
func NewReachabilityChecks(options ReachabilityOptions) (*ReachabilityChecks, error) {
	if err := ValidateProbes("postgres", options.Postgres); err != nil {
		return nil, err
	}
	if err := ValidateProbes("redis", options.Redis); err != nil {
		return nil, err
	}
	if err := ValidateProbes("storage", options.Storage); err != nil {
		return nil, err
	}
	return &ReachabilityChecks{
		postgres: append([]NamedProbe(nil), options.Postgres...),
		redis:    append([]NamedProbe(nil), options.Redis...),
		storage:  append([]NamedProbe(nil), options.Storage...),
	}, nil
}

// RunProbes executes one dependency group in configured order.
func RunProbes(ctx context.Context, kind string, probes []NamedProbe) error {
	for _, probe := range probes {
		if err := probe.Probe.Ping(ctx); err != nil {
			return fmt.Errorf("dbinit: %s %q is unreachable: %w", kind, probe.Name, err)
		}
	}
	return nil
}

// Run checks Postgres, then Redis, then S3-compatible storage.
func (r *ReachabilityChecks) Run(ctx context.Context) error {
	if err := RunProbes(ctx, "postgres", r.postgres); err != nil {
		return err
	}
	if err := RunProbes(ctx, "redis", r.redis); err != nil {
		return err
	}
	return RunProbes(ctx, "storage", r.storage)
}
