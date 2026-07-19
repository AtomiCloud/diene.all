// Command manager is the single composition root for the operator template. It
// wires N controllers into one binary with per-controller `--enable-<name>`
// flags and per-controller-scoped ledger config, runs with leader election on
// (even single-replica) and a secured metrics endpoint, and exposes health and
// readiness probes. This is the sole entry point in the repository (M35).
package main

import (
	"context"
	"errors"
	"flag"
	"os"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsfilters "sigs.k8s.io/controller-runtime/pkg/metrics/filters"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/AtomiCloud/diene.go-base/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/kube"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/ledgerstore"
	"github.com/AtomiCloud/diene.go-base/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.go-base/api/v1alpha1"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
)

// leaderElectionID is the per-instance leader-election lock identity.
const leaderElectionID = "operator-template.diene.atomi.cloud"

// errNoLedgerEndpoint is returned when the ledger-backed Note controller is
// enabled without a configured endpoint.
var errNoLedgerEndpoint = errors.New(
	"note controller enabled but --ledger-endpoint/LEDGER_ENDPOINT is empty; " +
		"set an endpoint or disable the Note controller (--enable-note=false)",
)

func main() {
	os.Exit(run())
}

func run() int {
	var (
		enableNote     bool
		enableJournal  bool
		observe        bool
		metricsAddr    string
		probeAddr      string
		leaderElect    bool
		brakeCap       int
		platform       string
		landscape      string
		ledgerEndpoint string
		ledgerBucket   string
		ledgerSecure   bool
		notePrefix     string
	)

	flag.BoolVar(&enableNote, "enable-note", true, "enable the Note controller")
	flag.BoolVar(&enableJournal, "enable-journal", true, "enable the Journal controller")
	flag.BoolVar(&observe, "observe", false, "run in observe mode: compute and report the plan without writing")
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8443", "secured metrics endpoint address")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "health/readiness probe address")
	flag.BoolVar(&leaderElect, "leader-elect", true, "enable leader election (on even for a single replica)")
	flag.IntVar(&brakeCap, "blast-brake-cap", 20, "destructive-write percentage-per-tick cap")
	flag.StringVar(&platform, "platform", "diene", "ledger platform coordinate")
	flag.StringVar(&landscape, "landscape", "lapras", "ledger landscape coordinate")
	flag.StringVar(&ledgerEndpoint, "ledger-endpoint", os.Getenv("LEDGER_ENDPOINT"), "S3/MinIO ledger endpoint host:port")
	flag.StringVar(&ledgerBucket, "ledger-bucket", envOr("LEDGER_BUCKET", "operator-template-ledger"), "ledger bucket name")
	flag.BoolVar(&ledgerSecure, "ledger-secure", os.Getenv("LEDGER_SECURE") == "true", "use TLS for the ledger endpoint")
	flag.StringVar(&notePrefix, "ledger-note-prefix", "notes/", "per-controller ledger object prefix for the Note controller")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	logger := zap.New(zap.UseFlagOptions(&opts))
	ctrl.SetLogger(logger)
	setupLog := ctrl.Log.WithName("setup")

	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		setupLog.Error(err, "register client-go scheme")
		return 1
	}
	if err := apiv1alpha1.AddToScheme(scheme); err != nil {
		setupLog.Error(err, "register sample scheme")
		return 1
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: scheme,
		Metrics: metricsserver.Options{
			BindAddress:    metricsAddr,
			SecureServing:  true,
			FilterProvider: metricsfilters.WithAuthenticationAndAuthorization,
		},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         leaderElect,
		LeaderElectionID:       leaderElectionID,
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		return 1
	}

	recorder := metrics.NewPrometheus()

	if enableNote {
		// The Note controller is ledger-backed: an enabled-but-empty endpoint is a
		// misconfiguration and is rejected early with a clear error rather than
		// crashing deep inside client construction.
		if ledgerEndpoint == "" {
			setupLog.Error(errNoLedgerEndpoint, "invalid configuration")
			return 1
		}
		noteLedger, ledgerErr := buildLedger(context.Background(), ledgerEndpoint, ledgerBucket, notePrefix, ledgerSecure)
		if ledgerErr != nil {
			setupLog.Error(ledgerErr, "build note ledger")
			return 1
		}
		noteController := &controllers.NoteReconciler{
			Client:     mgr.GetClient(),
			Clock:      kube.RealClock{},
			Recorder:   kube.NewEventRecorder(mgr.GetEventRecorderFor("note-controller")),
			ConfigMaps: kube.NewConfigMapAdapter(mgr.GetClient(), mgr.GetScheme(), controllers.NoteOwnerLabel),
			Ledger:     ledger.NewService(noteLedger),
			Metrics:    recorder,
			Observe:    observe,
			BrakeCap:   brakeCap,
			Platform:   platform,
			Landscape:  landscape,
		}
		if err := noteController.SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "wire Note controller")
			return 1
		}
	}

	if enableJournal {
		journalController := &controllers.JournalReconciler{
			Client:   mgr.GetClient(),
			Clock:    kube.RealClock{},
			Recorder: kube.NewEventRecorder(mgr.GetEventRecorderFor("journal-controller")),
			Metrics:  recorder,
		}
		if err := journalController.SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "wire Journal controller")
			return 1
		}
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "add healthz check")
		return 1
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "add readyz check")
		return 1
	}

	setupLog.Info("starting manager", "observe", observe, "leaderElect", leaderElect)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "run manager")
		return 1
	}
	return 0
}

// buildLedger constructs a per-controller-scoped ledger store and ensures its
// bucket. The S3/MinIO client construction (and its transport error branch) lives
// here in the composition root, outside the adapter coverage scope.
func buildLedger(ctx context.Context, endpoint, bucket, prefix string, secure bool) (*ledgerstore.MinioStore, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(os.Getenv("LEDGER_ACCESS_KEY"), os.Getenv("LEDGER_SECRET_KEY"), ""),
		Secure: secure,
	})
	if err != nil {
		return nil, err
	}
	store := ledgerstore.NewMinioStore(client, bucket, prefix)
	if err := store.EnsureBucket(ctx); err != nil {
		return nil, err
	}
	return store, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
