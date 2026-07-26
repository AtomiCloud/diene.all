package dbinit

import (
	"context"
	"errors"
	"fmt"
)

// Runner is one no-result db-init phase.
type Runner interface {
	Run(ctx context.Context) error
}

// Seeder is the idempotent seed phase.
type Seeder interface {
	Run(ctx context.Context) (int, error)
}

// InitializerOptions configures the ordered db-init phases.
type InitializerOptions struct {
	Reachability Runner
	Buckets      Runner
	Migrations   Runner
	Seeds        Seeder
}

// Initializer runs reachability, bucket creation, migrations, and seeds.
type Initializer struct {
	reachability Runner
	buckets      Runner
	migrations   Runner
	seeds        Seeder
}

// NewInitializer creates the one-shot phase coordinator.
func NewInitializer(options InitializerOptions) (*Initializer, error) {
	if options.Reachability == nil {
		return nil, errors.New("dbinit: reachability phase is required")
	}
	if options.Buckets == nil {
		return nil, errors.New("dbinit: bucket phase is required")
	}
	if options.Migrations == nil {
		return nil, errors.New("dbinit: migration phase is required")
	}
	if options.Seeds == nil {
		return nil, errors.New("dbinit: seed phase is required")
	}
	return &Initializer{
		reachability: options.Reachability,
		buckets:      options.Buckets,
		migrations:   options.Migrations,
		seeds:        options.Seeds,
	}, nil
}

// Run executes all phases in the contract-defined order.
func (i *Initializer) Run(ctx context.Context) (Result, error) {
	if err := i.reachability.Run(ctx); err != nil {
		return Result{}, fmt.Errorf("dbinit: reachability failed: %w", err)
	}
	if err := i.buckets.Run(ctx); err != nil {
		return Result{}, fmt.Errorf("dbinit: bucket creation failed: %w", err)
	}
	if err := i.migrations.Run(ctx); err != nil {
		return Result{}, fmt.Errorf("dbinit: migrations failed: %w", err)
	}
	seeded, err := i.seeds.Run(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("dbinit: seeds failed: %w", err)
	}
	return Result{Seeded: seeded}, nil
}
