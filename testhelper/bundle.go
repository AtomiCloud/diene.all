package testhelper

import (
	apith "github.com/AtomiCloud/diene.go-api-engine/testhelper"
	authth "github.com/AtomiCloud/diene.go-auth-engine/testhelper"
	configth "github.com/AtomiCloud/diene.go-config/testhelper"
	problemth "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	otelth "github.com/AtomiCloud/diene.go-otel/testhelper"
	presetth "github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// --- errors-problems -------------------------------------------------------

// ProblemOption is one expectation about a Problem envelope.
type ProblemOption = problemth.Option

var (
	// ProblemExpectID expects a Problem whose type URI ends in the given id.
	ProblemExpectID = problemth.ExpectID
	// ProblemExpectType expects an exact Problem type URI.
	ProblemExpectType = problemth.ExpectType
	// ProblemExpectTitle expects a Problem title.
	ProblemExpectTitle = problemth.ExpectTitle
	// ProblemExpectStatus expects a Problem status code.
	ProblemExpectStatus = problemth.ExpectStatus
	// ProblemExpectDetail expects a Problem detail string.
	ProblemExpectDetail = problemth.ExpectDetail
	// ProblemExpectInstance expects a Problem instance reference.
	ProblemExpectInstance = problemth.ExpectInstance
	// ProblemExpectRecoverable expects a Problem's recoverable flag.
	ProblemExpectRecoverable = problemth.ExpectRecoverable
	// ProblemExpectData expects a Problem's `data` extension.
	ProblemExpectData = problemth.ExpectData
	// ProblemCheckError reports why an error is not the expected Problem.
	ProblemCheckError = problemth.CheckError
	// ProblemAssertError fails the test unless an error is the expected Problem.
	ProblemAssertError = problemth.AssertError
	// ProblemCheckProblem reports why a Problem envelope misses expectations.
	ProblemCheckProblem = problemth.CheckProblem
	// ProblemAssertProblem fails the test unless a Problem envelope matches.
	ProblemAssertProblem = problemth.AssertProblem
	// ProblemSampleErrorPortal is a ready error portal for fixtures.
	ProblemSampleErrorPortal = problemth.SampleErrorPortal
	// ProblemSample is a ready Problem envelope for fixtures.
	ProblemSample = problemth.SampleProblem
)

// --- interfaces ------------------------------------------------------------

type (
	// InMemorySystem is the interfaces sibling's deterministic System seam.
	InMemorySystem = interfacesth.InMemorySystem
	// InMemorySystemOptions configures an [InMemorySystem].
	InMemorySystemOptions = interfacesth.InMemorySystemOptions
	// InMemoryVfs is the interfaces sibling's in-memory filesystem seam.
	InMemoryVfs = interfacesth.InMemoryVfs
	// InMemoryVfsOptions configures an [InMemoryVfs].
	InMemoryVfsOptions = interfacesth.InMemoryVfsOptions
	// InMemoryTerminal is the interfaces sibling's scripted Terminal seam.
	InMemoryTerminal = interfacesth.InMemoryTerminal
)

var (
	// NewInMemorySystem creates a deterministic clock and environment seam.
	NewInMemorySystem = interfacesth.NewInMemorySystem
	// NewInMemoryVfs creates an in-memory filesystem seam.
	NewInMemoryVfs = interfacesth.NewInMemoryVfs
	// NewInMemoryTerminal creates a scripted process-execution seam, which is
	// what lets the harness test its own compiled-artifact driver without ever
	// compiling an artifact.
	NewInMemoryTerminal = interfacesth.NewInMemoryTerminal
)

// --- config ----------------------------------------------------------------

var (
	// ConfigRequireConfig fails the test unless a configuration loaded.
	ConfigRequireConfig = configth.RequireConfig
	// ConfigRequireLoadError fails the test unless loading failed.
	ConfigRequireLoadError = configth.RequireLoadError
	// ConfigRequireIssue fails the test unless a validation issue names a path.
	ConfigRequireIssue = configth.RequireIssue
	// ConfigStub builds a configuration straight from a raw map.
	ConfigStub = configth.StubConfig
	// ConfigStubApp builds a configuration carrying only an app block.
	ConfigStubApp = configth.StubApp
	// ConfigBaseSource wraps a base document as a YAML source.
	ConfigBaseSource = configth.BaseSource
	// ConfigOverlaySource wraps a landscape overlay as a YAML source.
	ConfigOverlaySource = configth.OverlaySource
	// ConfigEnvSource wraps environment variables as an env source.
	ConfigEnvSource = configth.EnvSource
	// ConfigInvalidSchemaBlock is a block that fails schema composition.
	ConfigInvalidSchemaBlock = configth.InvalidSchemaBlock
)

// --- otel ------------------------------------------------------------------
//
// These are the INTERFACE MOCKS, and they are the only telemetry test double
// the family ships. There is no fake OTLP collector anywhere in this module
// (G1): the integration tier asserts emission through these mocks, and real
// export is proven at SIT against the preview environment's collector.

type (
	// OtelLoggerSink is the otel sibling's in-memory LoggerSink mock.
	OtelLoggerSink = otelth.InMemoryLoggerSink
	// OtelMetricsCollector is the otel sibling's in-memory MetricsCollector mock.
	OtelMetricsCollector = otelth.InMemoryMetricsCollector
	// OtelTraceEmitter is the otel sibling's in-memory TraceEmitter mock.
	OtelTraceEmitter = otelth.InMemoryTraceEmitter
)

var (
	// NewOtelLoggerSink creates the in-memory logger-sink mock.
	NewOtelLoggerSink = otelth.NewInMemoryLoggerSink
	// NewOtelMetricsCollector creates the in-memory metrics-collector mock.
	NewOtelMetricsCollector = otelth.NewInMemoryMetricsCollector
	// NewOtelTraceEmitter creates the in-memory trace-emitter mock.
	NewOtelTraceEmitter = otelth.NewInMemoryTraceEmitter
	// OtelAssertLogRecords fails the test unless the emitted logs match.
	OtelAssertLogRecords = otelth.AssertLogRecords
	// OtelAssertMetricRecords fails the test unless the emitted metrics match.
	OtelAssertMetricRecords = otelth.AssertMetricRecords
	// OtelAssertTraceRecords fails the test unless the emitted traces match.
	OtelAssertTraceRecords = otelth.AssertTraceRecords
	// OtelAssertResourceAttributes fails the test unless the semconv and
	// `atomi.*` resource attributes match.
	OtelAssertResourceAttributes = otelth.AssertResourceAttributes
	// OtelSampleConfig is a ready otel configuration block.
	OtelSampleConfig = otelth.SampleConfig
	// OtelSampleIdentity is a ready otel application identity.
	OtelSampleIdentity = otelth.SampleIdentity
)

// --- auth-engine -----------------------------------------------------------

type (
	// AuthFakeIDP is the auth-engine sibling's fake identity provider.
	AuthFakeIDP = authth.FakeIDP
	// AuthFakeIDPOptions configures an [AuthFakeIDP].
	AuthFakeIDPOptions = authth.FakeIDPOptions
	// AuthFakeProvider is the auth-engine sibling's scripted token provider.
	AuthFakeProvider = authth.FakeProvider
	// AuthFakeProviderOptions configures an [AuthFakeProvider].
	AuthFakeProviderOptions = authth.FakeProviderOptions
)

var (
	// AuthNewFakeIDP creates a fake IdP with real JWKS material.
	AuthNewFakeIDP = authth.NewFakeIDP
	// AuthNewFakeProvider creates a scripted token provider.
	AuthNewFakeProvider = authth.NewFakeProvider
	// AuthNewMemoryTokenStore creates an in-memory access-token store.
	AuthNewMemoryTokenStore = authth.NewMemoryTokenStore
	// AuthNewMemoryRefreshStore creates an in-memory rotating-refresh store.
	AuthNewMemoryRefreshStore = authth.NewMemoryRefreshStore
	// AuthAssertProblem fails the test unless an error is the expected auth
	// problem.
	AuthAssertProblem = authth.AssertAuthProblem
	// AuthAssertOwnershipDenied fails the test unless ownership was refused.
	AuthAssertOwnershipDenied = authth.AssertOwnershipDenied
)

// --- api-engine ------------------------------------------------------------

type (
	// APIFakeBackend is the api-engine sibling's fake HTTP backend.
	APIFakeBackend = apith.FakeBackend
	// APIFakeBackendOptions configures an [APIFakeBackend].
	APIFakeBackendOptions = apith.FakeBackendOptions
	// APIRoute is one canned route on a fake backend.
	APIRoute = apith.Route
	// APIProblemOptions describes a canned Problem-envelope response.
	APIProblemOptions = apith.ProblemOptions
)

var (
	// APINewFakeBackend creates a fake backend for the client tree.
	APINewFakeBackend = apith.NewFakeBackend
	// APINewFakeTree creates a fake multi-backend client tree.
	APINewFakeTree = apith.NewFakeTree
	// APINewFakeRetriever creates a fake per-backend token retriever.
	APINewFakeRetriever = apith.NewFakeRetriever
	// APICanned builds a canned Problem-envelope route.
	APICanned = apith.Canned
	// APIAssertProblem fails the test unless an error is the expected backend
	// problem.
	APIAssertProblem = apith.AssertProblem
	// APIAssertOutcome fails the test unless the 3-case classification matches.
	APIAssertOutcome = apith.AssertOutcome
)

// --- standard-config -------------------------------------------------------

type (
	// PresetRuntime is the container runtime the preset helpers start on.
	PresetRuntime = presetth.Runtime
	// PresetContainer is one started container.
	PresetContainer = presetth.Container
	// PresetDockerRuntime is the real Docker-backed runtime.
	PresetDockerRuntime = presetth.DockerRuntime
	// PresetPostgresOptions configures a Postgres preset container.
	PresetPostgresOptions = presetth.PostgresOptions
	// PresetRedisOptions configures a cache or kv preset container.
	PresetRedisOptions = presetth.RedisOptions
	// PresetStorageOptions configures a storage preset container.
	PresetStorageOptions = presetth.StorageOptions
	// PresetStartedPostgres is a started Postgres preset and its config block.
	PresetStartedPostgres = presetth.StartedPostgres
	// PresetStartedCache is a started cache preset and its config block.
	PresetStartedCache = presetth.StartedCache
	// PresetStartedKv is a started kv preset and its config block.
	PresetStartedKv = presetth.StartedKv
	// PresetStartedStorage is a started storage preset and its config block.
	PresetStartedStorage = presetth.StartedStorage
)

// PresetDefaultKey is the connection key the preset helpers emit by default.
const PresetDefaultKey = presetth.DefaultKey

var (
	// PresetStartPostgres boots a Postgres container and emits its block.
	PresetStartPostgres = presetth.StartPostgres
	// PresetStartCache boots a cache container and emits its block.
	PresetStartCache = presetth.StartCache
	// PresetStartKv boots a kv container and emits its block.
	PresetStartKv = presetth.StartKv
	// PresetStartStorage boots a storage container and emits its block.
	PresetStartStorage = presetth.StartStorage
	// PresetCreateBucket creates the bucket a storage entry addresses.
	PresetCreateBucket = presetth.CreateBucket
	// PresetFakePostgres is a Postgres block that addresses nothing, for tests
	// that need shape rather than a live dependency.
	PresetFakePostgres = presetth.FakePostgres
	// PresetFakeCache is a cache block that addresses nothing.
	PresetFakeCache = presetth.FakeCache
	// PresetFakeKv is a kv block that addresses nothing.
	PresetFakeKv = presetth.FakeKv
	// PresetFakeStorage is a storage block that addresses nothing.
	PresetFakeStorage = presetth.FakeStorage
)

// PresetRequireEntry fails the test unless a keyed preset block carries key.
//
// It is a wrapper rather than an alias because Go cannot bind a generic
// function to a variable, and a bundle that silently dropped the generic
// helpers would send consumers back to the sibling import it exists to replace.
func PresetRequireEntry[Entry any](t TestingT, block map[string]Entry, key string) Entry {
	t.Helper()
	return presetth.RequireEntry(t, block, key)
}

// PresetRequireStarted fails the test unless a preset container started.
func PresetRequireStarted[Started any](t TestingT, started *Started, err error) *Started {
	t.Helper()
	return presetth.RequireStarted(t, started, err)
}
