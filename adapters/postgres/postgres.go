// Package postgres adapts pgx pools to the go-consumer persistence ports.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"

	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-consumer/lib/seedrecord"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PoolAPI is the pgx surface used by Pool and its deterministic tests.
type PoolAPI interface {
	Ping(ctx context.Context) error
	Exec(ctx context.Context, sql string, arguments ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	Close()
}

// Factory creates a pool from a fully escaped pgx connection string.
type Factory func(context.Context, string) (PoolAPI, error)

// Pool is an instrumented Postgres connection pool.
type Pool struct {
	pool   PoolAPI
	tracer *tracing.Tracer
}

// Open constructs a pgx pool from the standard-config connection entry.
func Open(ctx context.Context, entry standardconfig.PostgresEntry, tracer *tracing.Tracer) (*Pool, error) {
	return OpenWithFactory(ctx, entry, tracer, func(factoryCtx context.Context, connectionString string) (PoolAPI, error) {
		return pgxpool.New(factoryCtx, connectionString)
	})
}

// OpenWithFactory constructs a pool through an injected factory.
func OpenWithFactory(
	ctx context.Context,
	entry standardconfig.PostgresEntry,
	tracer *tracing.Tracer,
	factory Factory,
) (*Pool, error) {
	if err := validateEntry(entry); err != nil {
		return nil, err
	}
	if factory == nil {
		return nil, errors.New("postgres: pool factory is required")
	}
	query := url.Values{}
	if entry.SSL {
		query.Set("sslmode", "require")
	} else {
		query.Set("sslmode", "disable")
	}
	query.Set("pool_min_conns", strconv.Itoa(entry.Pool.Min))
	query.Set("pool_max_conns", strconv.Itoa(entry.Pool.Max))
	connectionURL := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(entry.Username, entry.Password),
		Host:     net.JoinHostPort(entry.Host, strconv.Itoa(entry.Port)),
		Path:     entry.Database,
		RawQuery: query.Encode(),
	}
	driver, err := factory(ctx, connectionURL.String())
	if err != nil {
		return nil, fmt.Errorf("postgres: open pool: %w", err)
	}
	pool, err := New(driver, tracer)
	if err != nil {
		driver.Close()
		return nil, err
	}
	return pool, nil
}

// New wraps an existing pgx-compatible pool.
func New(pool PoolAPI, tracer *tracing.Tracer) (*Pool, error) {
	if pool == nil {
		return nil, errors.New("postgres: pool is required")
	}
	if tracer == nil {
		return nil, errors.New("postgres: tracer is required")
	}
	return &Pool{pool: pool, tracer: tracer}, nil
}

// Ping checks database reachability.
func (p *Pool) Ping(ctx context.Context) error {
	span, err := p.tracer.Start("postgres.ping", nil)
	if err != nil {
		return err
	}
	return span.End(p.pool.Ping(ctx))
}

// Exec executes a statement and returns its affected-row count.
func (p *Pool) Exec(ctx context.Context, statement string, arguments ...any) (int64, error) {
	if strings.TrimSpace(statement) == "" {
		return 0, errors.New("postgres: statement is required")
	}
	span, err := p.tracer.Start("postgres.exec", nil)
	if err != nil {
		return 0, err
	}
	tag, operationErr := p.pool.Exec(ctx, statement, arguments...)
	if endErr := span.End(operationErr); endErr != nil {
		return 0, endErr
	}
	return tag.RowsAffected(), nil
}

// QueryInt64 executes a query that returns exactly one signed integer value.
func (p *Pool) QueryInt64(ctx context.Context, query string, arguments ...any) (int64, error) {
	if strings.TrimSpace(query) == "" {
		return 0, errors.New("postgres: query is required")
	}
	span, err := p.tracer.Start("postgres.query", nil)
	if err != nil {
		return 0, err
	}
	var value int64
	operationErr := p.pool.QueryRow(ctx, query, arguments...).Scan(&value)
	if endErr := span.End(operationErr); endErr != nil {
		return 0, endErr
	}
	return value, nil
}

// PrepareMigrations creates the migration ledger when it is absent.
func (p *Pool) PrepareMigrations(ctx context.Context) error {
	_, err := p.Exec(ctx, `CREATE TABLE IF NOT EXISTS diene_migrations (
name TEXT PRIMARY KEY,
applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`)
	return err
}

// AppliedMigrations lists applied migration names in stable order.
func (p *Pool) AppliedMigrations(ctx context.Context) ([]string, error) {
	return p.queryStrings(ctx, "postgres.applied_migrations", "SELECT name FROM diene_migrations ORDER BY name")
}

// ApplyMigration executes one validated statement and records its name in the
// same implicit Postgres transaction.
func (p *Pool) ApplyMigration(ctx context.Context, name, statement string) error {
	if !validMigrationName(name) {
		return errors.New("postgres: migration name must contain only letters, digits, dot, dash, or underscore")
	}
	if strings.TrimSpace(statement) == "" {
		return errors.New("postgres: migration statement is required")
	}
	ledgerStatement := statement + ";\nINSERT INTO diene_migrations (name) VALUES ('" + name + "') ON CONFLICT (name) DO NOTHING"
	_, err := p.Exec(ctx, ledgerStatement)
	return err
}

// Insert persists a processed message idempotently.
func (p *Pool) Insert(ctx context.Context, record domain.ProcessedMessageRecord) (bool, error) {
	if strings.TrimSpace(record.ID) == "" {
		return false, errors.New("postgres: processed message id is required")
	}
	affected, err := p.Exec(ctx, `INSERT INTO processed_messages (id, object_key, payload, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (id) DO NOTHING`, record.ID, record.ObjectKey, record.Payload, record.CreatedAt.UTC())
	if err != nil {
		return false, err
	}
	return affected > 0, nil
}

// ExistingSeedIDs lists seed ids already present in the database.
func (p *Pool) ExistingSeedIDs(ctx context.Context) ([]string, error) {
	return p.queryStrings(ctx, "postgres.existing_seed_ids", "SELECT id FROM seed_records ORDER BY id")
}

// InsertSeed persists one seed record idempotently.
func (p *Pool) InsertSeed(ctx context.Context, record seedrecord.Record) (bool, error) {
	if strings.TrimSpace(record.ID) == "" {
		return false, errors.New("postgres: seed id is required")
	}
	affected, err := p.Exec(ctx, `INSERT INTO seed_records (id, value)
VALUES ($1, $2)
ON CONFLICT (id) DO NOTHING`, record.ID, record.Value)
	if err != nil {
		return false, err
	}
	return affected > 0, nil
}

// Close releases all pool resources.
func (p *Pool) Close() error {
	p.pool.Close()
	return nil
}

func (p *Pool) queryStrings(ctx context.Context, spanName, query string) ([]string, error) {
	span, err := p.tracer.Start(spanName, nil)
	if err != nil {
		return nil, err
	}
	rows, operationErr := p.pool.Query(ctx, query)
	if operationErr != nil {
		return nil, span.End(operationErr)
	}
	defer rows.Close()
	values := make([]string, 0)
	for rows.Next() {
		var value string
		if scanErr := rows.Scan(&value); scanErr != nil {
			return nil, span.End(scanErr)
		}
		values = append(values, value)
	}
	if rowsErr := rows.Err(); rowsErr != nil {
		return nil, span.End(rowsErr)
	}
	if endErr := span.End(nil); endErr != nil {
		return nil, endErr
	}
	return values, nil
}

func validateEntry(entry standardconfig.PostgresEntry) error {
	switch {
	case strings.TrimSpace(entry.Host) == "":
		return errors.New("postgres: host is required")
	case entry.Port < 1 || entry.Port > 65535:
		return errors.New("postgres: port must be between 1 and 65535")
	case strings.TrimSpace(entry.Database) == "":
		return errors.New("postgres: database is required")
	case strings.TrimSpace(entry.Username) == "":
		return errors.New("postgres: username is required")
	case entry.Pool.Min < 0:
		return errors.New("postgres: pool minimum must not be negative")
	case entry.Pool.Max < 1:
		return errors.New("postgres: pool maximum must be positive")
	case entry.Pool.Min > entry.Pool.Max:
		return errors.New("postgres: pool minimum must not exceed maximum")
	default:
		return nil
	}
}

func validMigrationName(name string) bool {
	if name == "" {
		return false
	}
	for _, character := range name {
		if character >= 'a' && character <= 'z' ||
			character >= 'A' && character <= 'Z' ||
			character >= '0' && character <= '9' ||
			character == '.' || character == '-' || character == '_' {
			continue
		}
		return false
	}
	return true
}
