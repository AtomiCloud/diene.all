package sit_test

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	consumerapp "github.com/AtomiCloud/diene.go-consumer/cmd/go-consumer/app"
	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-e2e/adapters/process"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/preview"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5"
	redis "github.com/redis/go-redis/v9"
)

const journeyTimeout = 2 * time.Minute

type sitHarness struct {
	root      string
	target    preview.Target
	problems  *e2e.Problems
	compiled  e2e.Driver
	inProcess e2e.Driver
}

func newSITHarness(t *testing.T) *sitHarness {
	t.Helper()
	root := requiredEnvironment(t, "GO_CONSUMER_ROOT")
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		t.Fatalf("resolve repository root: %v", err)
	}
	artifact := requiredEnvironment(t, "CLI_BIN")
	if !filepath.IsAbs(artifact) {
		artifact = filepath.Join(absoluteRoot, artifact)
	}
	problems, err := e2e.NewProblems(problem.LocalErrorPortal())
	if err != nil {
		t.Fatalf("construct e2e problems: %v", err)
	}
	target, err := preview.Resolve(otelsdk.NewSystem(), problems)
	if err != nil {
		t.Fatalf("resolve preview target: %v", err)
	}
	environment := processEnvironment()
	environment["GO_CONSUMER_ROOT"] = absoluteRoot
	compiled, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact:         artifact,
		Terminal:         process.NewTerminal(process.TerminalOptions{}),
		Filesystem:       filesystem.NewVfs(),
		Environment:      environment,
		WorkingDirectory: absoluteRoot,
		Problems:         problems,
	})
	if err != nil {
		t.Fatalf("construct compiled driver: %v", err)
	}
	application := consumerapp.New(consumerapp.Options{Name: "go-consumer", PID: os.Getpid()})
	inProcess, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Entrypoint:       application.Execute,
		Environment:      environment,
		WorkingDirectory: absoluteRoot,
		Problems:         problems,
	})
	if err != nil {
		t.Fatalf("construct in-process driver: %v", err)
	}
	return &sitHarness{
		root: absoluteRoot, target: target, problems: problems,
		compiled: compiled, inProcess: inProcess,
	}
}

func (h *sitHarness) invocation(environment map[string]string, arguments ...string) e2e.Invocation {
	args := make([]string, 0, len(arguments)+2)
	args = append(args, "--landscape", h.target.Landscape)
	args = append(args, arguments...)
	return e2e.Invocation{Args: args, Env: environment, WorkingDirectory: h.root}
}

func (h *sitHarness) run(t *testing.T, journey e2e.Journey) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), journeyTimeout)
	defer cancel()
	mode := requiredEnvironment(t, "SIT_DRIVER")
	switch mode {
	case "binary":
		report, err := e2e.RunJourney(ctx, h.compiled, journey, h.problems)
		if err != nil {
			t.Fatalf("run %q with compiled driver: %v", journey.Name, err)
		}
		t.Logf("journey %q completed %d compiled steps", report.Journey, len(report.Steps))
	case "parity":
		compiled, inProcess, err := e2e.RunParity(ctx, h.compiled, h.inProcess, journey, h.problems)
		if err != nil {
			t.Fatalf("run %q in parity mode: %v", journey.Name, err)
		}
		t.Logf(
			"journey %q completed %d compiled and %d in-process steps",
			journey.Name,
			len(compiled.Steps),
			len(inProcess.Steps),
		)
	default:
		t.Fatalf("unsupported SIT_DRIVER %q", mode)
	}
}

func workerEnvironment(prefix string, id string) map[string]string {
	return map[string]string{
		"ATOMI_HEALTH__HEARTBEAT_FILE":    filepath.ToSlash(filepath.Join("dist", "run", prefix+"-"+id+".json")),
		"ATOMI_TRANSPORT__BATCH_SIZE":     "10",
		"ATOMI_TRANSPORT__BLOCK_MS":       "50",
		"ATOMI_TRANSPORT__CONSUMER_GROUP": prefix + "-group-" + id,
		"ATOMI_TRANSPORT__CONSUMER_NAME":  prefix + "-consumer-" + id,
		"ATOMI_TRANSPORT__IDLE_MS":        "0",
		"ATOMI_TRANSPORT__STREAM":         "sit." + prefix + "." + id,
	}
}

func processEnvironment() map[string]string {
	environment := make(map[string]string)
	for _, entry := range os.Environ() {
		key, value, found := strings.Cut(entry, "=")
		if found {
			environment[key] = value
		}
	}
	return environment
}

func requiredEnvironment(t *testing.T, name string) string {
	t.Helper()
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		t.Fatalf("required environment variable %s is blank", name)
	}
	return value
}

func environmentPort(t *testing.T, name string) int {
	t.Helper()
	value, err := strconv.Atoi(requiredEnvironment(t, name))
	if err != nil || value < 1 || value > 65535 {
		t.Fatalf("environment variable %s is not a port: %q", name, os.Getenv(name))
	}
	return value
}

func redisClient(t *testing.T) *redis.Client {
	t.Helper()
	client := redis.NewClient(&redis.Options{
		Addr: net.JoinHostPort(
			requiredEnvironment(t, "ATOMI_KV__MAIN__HOST"),
			strconv.Itoa(environmentPort(t, "ATOMI_KV__MAIN__PORT")),
		),
		DB:       environmentPortValue(t, "ATOMI_KV__MAIN__DB"),
		Password: os.Getenv("ATOMI_KV__MAIN__PASSWORD"),
	})
	t.Cleanup(func() {
		if err := client.Close(); err != nil {
			t.Errorf("close Redis client: %v", err)
		}
	})
	return client
}

func environmentPortValue(t *testing.T, name string) int {
	t.Helper()
	value, err := strconv.Atoi(requiredEnvironment(t, name))
	if err != nil || value < 0 {
		t.Fatalf("environment variable %s is not a non-negative integer: %q", name, os.Getenv(name))
	}
	return value
}

func postgresClient(ctx context.Context, t *testing.T) *pgx.Conn {
	t.Helper()
	connection := &url.URL{
		Scheme: "postgres",
		User: url.UserPassword(
			requiredEnvironment(t, "ATOMI_POSTGRES__MAIN__USERNAME"),
			requiredEnvironment(t, "ATOMI_POSTGRES__MAIN__PASSWORD"),
		),
		Host: net.JoinHostPort(
			requiredEnvironment(t, "ATOMI_POSTGRES__MAIN__HOST"),
			strconv.Itoa(environmentPort(t, "ATOMI_POSTGRES__MAIN__PORT")),
		),
		Path: requiredEnvironment(t, "ATOMI_POSTGRES__MAIN__DATABASE"),
	}
	query := connection.Query()
	query.Set("sslmode", "disable")
	connection.RawQuery = query.Encode()
	client, err := pgx.Connect(ctx, connection.String())
	if err != nil {
		t.Fatalf("connect to Postgres: %v", err)
	}
	t.Cleanup(func() {
		if closeErr := client.Close(context.Background()); closeErr != nil {
			t.Errorf("close Postgres client: %v", closeErr)
		}
	})
	return client
}

func storageClient(ctx context.Context, t *testing.T) *s3.Client {
	t.Helper()
	configuration, err := awsconfig.LoadDefaultConfig(
		ctx,
		awsconfig.WithRegion(requiredEnvironment(t, "SIT_STORAGE_REGION")),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			requiredEnvironment(t, "ATOMI_STORAGE__MAIN__ACCESS_KEY_ID"),
			requiredEnvironment(t, "ATOMI_STORAGE__MAIN__SECRET_ACCESS_KEY"),
			"",
		)),
	)
	if err != nil {
		t.Fatalf("construct storage configuration: %v", err)
	}
	return s3.NewFromConfig(configuration, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(requiredEnvironment(t, "ATOMI_STORAGE__MAIN__ENDPOINT"))
		options.UsePathStyle = true
	})
}

func newUUID(t *testing.T) string {
	t.Helper()
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		t.Fatalf("generate UUID: %v", err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(value[:])
	return encoded[0:8] + "-" + encoded[8:12] + "-" + encoded[12:16] + "-" + encoded[16:20] + "-" + encoded[20:32]
}

func waitFor(ctx context.Context, interval time.Duration, check func(context.Context) (bool, error)) error {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	var lastErr error
	for {
		ready, err := check(ctx)
		if ready {
			return nil
		}
		if err != nil {
			lastErr = err
		}
		select {
		case <-ctx.Done():
			return errors.Join(ctx.Err(), lastErr)
		case <-ticker.C:
		}
	}
}

func clickHouseCount(ctx context.Context, endpoint string, statement string) (int64, error) {
	requestURL, err := url.Parse(endpoint)
	if err != nil {
		return 0, fmt.Errorf("parse ClickHouse endpoint: %w", err)
	}
	query := requestURL.Query()
	query.Set("query", statement)
	requestURL.RawQuery = query.Encode()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL.String(), nil)
	if err != nil {
		return 0, fmt.Errorf("construct ClickHouse request: %w", err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return 0, fmt.Errorf("query ClickHouse: %w", err)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 64*1024))
	if err != nil {
		_ = response.Body.Close()
		return 0, fmt.Errorf("read ClickHouse response: %w", err)
	}
	if closeErr := response.Body.Close(); closeErr != nil {
		return 0, fmt.Errorf("close ClickHouse response: %w", closeErr)
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return 0, fmt.Errorf("ClickHouse returned %s: %s", response.Status, strings.TrimSpace(string(body)))
	}
	count, err := strconv.ParseInt(strings.TrimSpace(string(body)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse ClickHouse count %q: %w", strings.TrimSpace(string(body)), err)
	}
	return count, nil
}

type victoriaResponse struct {
	Data victoriaData `json:"data"`
}

type victoriaData struct {
	Result []json.RawMessage `json:"result"`
}

func victoriaMetricCount(ctx context.Context, endpoint string, expression string) (int, error) {
	requestURL, err := url.Parse(strings.TrimRight(endpoint, "/") + "/api/v1/query")
	if err != nil {
		return 0, fmt.Errorf("parse VictoriaMetrics endpoint: %w", err)
	}
	query := requestURL.Query()
	query.Set("query", expression)
	requestURL.RawQuery = query.Encode()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL.String(), nil)
	if err != nil {
		return 0, fmt.Errorf("construct VictoriaMetrics request: %w", err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return 0, fmt.Errorf("query VictoriaMetrics: %w", err)
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 64*1024))
		_ = response.Body.Close()
		return 0, fmt.Errorf("VictoriaMetrics returned %s: %s", response.Status, strings.TrimSpace(string(body)))
	}
	var result victoriaResponse
	if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
		_ = response.Body.Close()
		return 0, fmt.Errorf("decode VictoriaMetrics response: %w", err)
	}
	if closeErr := response.Body.Close(); closeErr != nil {
		return 0, fmt.Errorf("close VictoriaMetrics response: %w", closeErr)
	}
	return len(result.Data.Result), nil
}

func sqlLiteral(value string) string {
	return strings.ReplaceAll(value, "'", "''")
}
