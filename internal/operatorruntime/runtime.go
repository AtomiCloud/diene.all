// Package operatorruntime owns the manager's configuration and controller wiring.
package operatorruntime

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	metricsfilters "sigs.k8s.io/controller-runtime/pkg/metrics/filters"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/kube"
	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/ledgerstore"
	operatormetrics "github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/v1alpha1"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

const leaderElectionID = "fleet-operator.diene.atomi.cloud"

// ErrLedgerEndpointRequired reports an enabled Note controller without a ledger endpoint.
var ErrLedgerEndpointRequired = errors.New("note controller enabled but --ledger-endpoint/LEDGER_ENDPOINT is empty; set an endpoint or disable the Note controller (--enable-note=false)")

// ErrNoteLedgerRequired reports an enabled Note controller without its runtime dependency.
var ErrNoteLedgerRequired = errors.New("note controller enabled without a ledger service")

// Config is the manager configuration populated by its real command-line flags.
type Config struct {
	EnableNote       bool
	EnableJournal    bool
	EnableCluster    bool
	EnablePlatform   bool
	EnableDependency bool
	EnableTraffic    bool
	EnableWebhook    bool
	EnableCfDeploy   bool
	EnableProblem    bool
	Observe          bool
	MetricsAddress   string
	HealthAddress    string
	LeaderElection   bool
	BlastBrakeCap    int
	Platform         string
	Landscape        string
	LedgerEndpoint   string
	LedgerBucket     string
	LedgerSecure     bool
	LedgerNotePrefix string
	LedgerAccessKey  string
	LedgerSecretKey  string
}

// DefaultConfig returns production-safe defaults, including leader election and secured metrics.
func DefaultConfig(getenv func(string) string) Config {
	ledgerBucket := getenv("LEDGER_BUCKET")
	if ledgerBucket == "" {
		ledgerBucket = "fleet-operator-ledger"
	}
	return Config{
		EnableNote:       true,
		EnableJournal:    true,
		MetricsAddress:   ":8443",
		HealthAddress:    ":8081",
		LeaderElection:   true,
		BlastBrakeCap:    20,
		Platform:         "diene",
		Landscape:        "lapras",
		LedgerEndpoint:   getenv("LEDGER_ENDPOINT"),
		LedgerBucket:     ledgerBucket,
		LedgerSecure:     getenv("LEDGER_SECURE") == "true",
		LedgerNotePrefix: "notes/",
		LedgerAccessKey:  getenv("LEDGER_ACCESS_KEY"),
		LedgerSecretKey:  getenv("LEDGER_SECRET_KEY"),
	}
}

// BindFlags binds the manager's public runtime interface directly to config.
func BindFlags(flags *flag.FlagSet, config *Config) {
	flags.BoolVar(&config.EnableNote, "enable-note", config.EnableNote, "enable the Note controller")
	flags.BoolVar(&config.EnableJournal, "enable-journal", config.EnableJournal, "enable the Journal controller")
	flags.BoolVar(&config.Observe, "observe", config.Observe, "run in observe mode: compute and report the plan without writing")
	flags.StringVar(&config.MetricsAddress, "metrics-bind-address", config.MetricsAddress, "secured metrics endpoint address")
	flags.StringVar(&config.HealthAddress, "health-probe-bind-address", config.HealthAddress, "health/readiness probe address")
	flags.BoolVar(&config.LeaderElection, "leader-elect", config.LeaderElection, "enable leader election (on even for a single replica)")
	flags.IntVar(&config.BlastBrakeCap, "blast-brake-cap", config.BlastBrakeCap, "destructive-write percentage-per-tick cap")
	flags.StringVar(&config.Platform, "platform", config.Platform, "ledger platform coordinate")
	flags.StringVar(&config.Landscape, "landscape", config.Landscape, "ledger landscape coordinate")
	flags.StringVar(&config.LedgerEndpoint, "ledger-endpoint", config.LedgerEndpoint, "S3/MinIO ledger endpoint host:port")
	flags.StringVar(&config.LedgerBucket, "ledger-bucket", config.LedgerBucket, "ledger bucket name")
	flags.BoolVar(&config.LedgerSecure, "ledger-secure", config.LedgerSecure, "use TLS for the ledger endpoint")
	flags.StringVar(&config.LedgerNotePrefix, "ledger-note-prefix", config.LedgerNotePrefix, "per-controller ledger object prefix for the Note controller")
}

// ControllerDependencies contains replaceable runtime dependencies for registration tests.
type ControllerDependencies struct {
	Clock      kube.Clock
	Metrics    operatormetrics.Recorder
	NoteLedger *ledger.Service
}

// NewScheme returns the scheme used by both the production manager and fixtures.
func NewScheme() (*runtime.Scheme, error) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register client-go scheme: %w", err)
	}
	if err := apiv1alpha1.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register sample scheme: %w", err)
	}
	return scheme, nil
}

// NewManager constructs the controller-runtime manager without registering controllers.
func NewManager(restConfig *rest.Config, scheme *runtime.Scheme, config Config) (ctrl.Manager, error) {
	return ctrl.NewManager(restConfig, ctrl.Options{
		Scheme: scheme,
		Metrics: metricsserver.Options{
			BindAddress:    config.MetricsAddress,
			SecureServing:  true,
			FilterProvider: metricsfilters.WithAuthenticationAndAuthorization,
		},
		HealthProbeBindAddress: config.HealthAddress,
		LeaderElection:         config.LeaderElection,
		LeaderElectionID:       leaderElectionID,
	})
}

// RegisterControllers applies the real per-controller enable flags to manager registration.
func RegisterControllers(manager ctrl.Manager, config Config, dependencies ControllerDependencies) error {
	clock := dependencies.Clock
	if clock == nil {
		clock = kube.RealClock{}
	}
	recorder := dependencies.Metrics
	if recorder == nil {
		recorder = operatormetrics.NewPrometheus()
	}

	if config.EnableNote {
		if dependencies.NoteLedger == nil {
			return ErrNoteLedgerRequired
		}
		reconciler := &controllers.NoteReconciler{
			Client:     manager.GetClient(),
			Clock:      clock,
			Recorder:   kube.NewEventRecorder(manager.GetEventRecorderFor("note-controller")),
			ConfigMaps: kube.NewConfigMapAdapter(manager.GetClient(), manager.GetScheme(), controllers.NoteOwnerLabel),
			Ledger:     *dependencies.NoteLedger,
			Metrics:    recorder,
			Observe:    config.Observe,
			BrakeCap:   config.BlastBrakeCap,
			Platform:   config.Platform,
			Landscape:  config.Landscape,
		}
		if err := reconciler.SetupWithManager(manager); err != nil {
			return fmt.Errorf("register Note controller: %w", err)
		}
	}

	if config.EnableJournal {
		reconciler := &controllers.JournalReconciler{
			Client:   manager.GetClient(),
			Clock:    clock,
			Recorder: kube.NewEventRecorder(manager.GetEventRecorderFor("journal-controller")),
			Metrics:  recorder,
		}
		if err := reconciler.SetupWithManager(manager); err != nil {
			return fmt.Errorf("register Journal controller: %w", err)
		}
	}
	return nil
}

// AddHealthChecks registers the manager's health and readiness endpoints.
func AddHealthChecks(manager ctrl.Manager) error {
	if err := manager.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		return fmt.Errorf("add healthz check: %w", err)
	}
	if err := manager.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		return fmt.Errorf("add readyz check: %w", err)
	}
	return nil
}

// Start constructs and runs the production manager until context cancellation.
func Start(ctx context.Context, restConfig *rest.Config, config Config) error {
	scheme, err := NewScheme()
	if err != nil {
		return err
	}
	manager, err := NewManager(restConfig, scheme, config)
	if err != nil {
		return fmt.Errorf("create manager: %w", err)
	}
	dependencies, err := productionDependencies(ctx, config)
	if err != nil {
		return err
	}
	if err := RegisterControllers(manager, config, dependencies); err != nil {
		return err
	}
	if err := AddHealthChecks(manager); err != nil {
		return err
	}
	ctrl.Log.WithName("setup").Info("starting manager", "observe", config.Observe, "leaderElect", config.LeaderElection)
	return manager.Start(ctx)
}

func productionDependencies(ctx context.Context, config Config) (ControllerDependencies, error) {
	dependencies := ControllerDependencies{Clock: kube.RealClock{}, Metrics: operatormetrics.NewPrometheus()}
	if !config.EnableNote {
		return dependencies, nil
	}
	if config.LedgerEndpoint == "" {
		return ControllerDependencies{}, ErrLedgerEndpointRequired
	}
	client, err := minio.New(config.LedgerEndpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(config.LedgerAccessKey, config.LedgerSecretKey, ""),
		Secure: config.LedgerSecure,
	})
	if err != nil {
		return ControllerDependencies{}, fmt.Errorf("build ledger client: %w", err)
	}
	store := ledgerstore.NewMinioStore(client, config.LedgerBucket, config.LedgerNotePrefix)
	// Bound the startup bucket check: a black-holed ledger endpoint must fail fast
	// rather than block manager.Start (and the health server) indefinitely.
	bctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := store.EnsureBucket(bctx); err != nil {
		return ControllerDependencies{}, fmt.Errorf("ensure ledger bucket: %w", err)
	}
	service := ledger.NewService(store)
	dependencies.NoteLedger = &service
	return dependencies, nil
}
