// Package operatorruntime owns the manager's configuration and controller wiring.
package operatorruntime

import (
	"context"
	"flag"
	"fmt"

	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	metricsfilters "sigs.k8s.io/controller-runtime/pkg/metrics/filters"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/AtomiCloud/diene.boron/adapters/operator/cloudflare"
	"github.com/AtomiCloud/diene.boron/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.boron/adapters/operator/kube"
	operatormetrics "github.com/AtomiCloud/diene.boron/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.boron/api/v1alpha1"
	"github.com/AtomiCloud/diene.boron/lib/operator/reconcile"
)

const leaderElectionID = "boron.atomi.cloud"

// Config is the manager configuration populated by its real command-line flags.
type Config struct {
	EnableAccount  bool
	EnableTunnel   bool
	EnableExposure bool
	MetricsAddress string
	HealthAddress  string
	LeaderElection bool

	// Installation identity (trusted Garden-supplied profile metadata; never CR
	// input). Profile is lapras, ditto, or registered; hosted/hermetic profiles
	// are refused at admission.
	Profile      string
	Connected    bool
	DittoEnabled bool
	Landscape    string
	Instance     string

	// CloudflaredImage pins the cloudflared tunnel client image.
	CloudflaredImage string
	// FakeCloudflare swaps the real provider for the in-memory fake (SIT/e2e
	// against a fake-CF adapter — never used against real credentials).
	FakeCloudflare bool
}

// DefaultConfig returns production-safe defaults, including leader election and secured metrics.
func DefaultConfig(getenv func(string) string) Config {
	image := getenv("CLOUDFLARED_IMAGE")
	if image == "" {
		image = "cloudflare/cloudflared:2025.7.0"
	}
	return Config{
		EnableAccount:    true,
		EnableTunnel:     true,
		EnableExposure:   true,
		MetricsAddress:   ":8443",
		HealthAddress:    ":8081",
		LeaderElection:   true,
		Profile:          reconcile.ProfileLapras,
		Connected:        false,
		Landscape:        "lapras",
		CloudflaredImage: image,
	}
}

// BindFlags binds the manager's public runtime interface directly to config.
func BindFlags(flags *flag.FlagSet, config *Config) {
	flags.BoolVar(&config.EnableAccount, "enable-account", config.EnableAccount, "enable the Account controller")
	flags.BoolVar(&config.EnableTunnel, "enable-tunnel", config.EnableTunnel, "enable the Tunnel controller")
	flags.BoolVar(&config.EnableExposure, "enable-exposure", config.EnableExposure, "enable the Exposure controller")
	flags.StringVar(&config.MetricsAddress, "metrics-bind-address", config.MetricsAddress, "secured metrics endpoint address")
	flags.StringVar(&config.HealthAddress, "health-probe-bind-address", config.HealthAddress, "health/readiness probe address")
	flags.BoolVar(&config.LeaderElection, "leader-elect", config.LeaderElection, "enable leader election (on even for a single replica)")
	flags.StringVar(&config.Profile, "install-profile", config.Profile, "installation profile: lapras, ditto, or registered")
	flags.BoolVar(&config.Connected, "connected", config.Connected, "the profile is connected (required for lapras/ditto exposure programming)")
	flags.BoolVar(&config.DittoEnabled, "ditto-inspect", config.DittoEnabled, "explicitly enable Boron on a ditto inspection run")
	flags.StringVar(&config.Landscape, "landscape", config.Landscape, "trusted profile landscape every Exposure must declare")
	flags.StringVar(&config.Instance, "instance", config.Instance, "trusted profile instance every Exposure must declare")
	flags.StringVar(&config.CloudflaredImage, "cloudflared-image", config.CloudflaredImage, "cloudflared tunnel client image")
	flags.BoolVar(&config.FakeCloudflare, "fake-cloudflare", config.FakeCloudflare, "use the in-memory fake Cloudflare adapter (SIT/e2e only)")
}

// Installation projects the trusted installation identity for the reconcilers.
func (c Config) Installation() reconcile.Installation {
	return reconcile.Installation{
		Profile:      c.Profile,
		Connected:    c.Connected,
		DittoEnabled: c.DittoEnabled,
		Landscape:    c.Landscape,
		Instance:     c.Instance,
	}
}

// ControllerDependencies contains replaceable runtime dependencies for registration tests.
type ControllerDependencies struct {
	Clock    kube.Clock
	Metrics  operatormetrics.Recorder
	Provider cloudflare.Port
}

// NewScheme returns the scheme used by both the production manager and fixtures.
func NewScheme() (*runtime.Scheme, error) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register client-go scheme: %w", err)
	}
	if err := apiv1alpha1.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register boron scheme: %w", err)
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
	provider := dependencies.Provider
	if provider == nil {
		provider = cloudflare.NewMemory()
	}

	secrets := kube.NewSecretAdapter(manager.GetClient())

	if config.EnableAccount {
		reconciler := &controllers.AccountReconciler{
			Client:   manager.GetClient(),
			Clock:    clock,
			Recorder: kube.NewEventRecorder(manager.GetEventRecorderFor("account-controller")),
			Secrets:  secrets,
			Provider: provider,
			Metrics:  recorder,
		}
		if err := reconciler.SetupWithManager(manager); err != nil {
			return fmt.Errorf("register Account controller: %w", err)
		}
	}

	if config.EnableTunnel {
		reconciler := &controllers.TunnelReconciler{
			Client:           manager.GetClient(),
			Clock:            clock,
			Recorder:         kube.NewEventRecorder(manager.GetEventRecorderFor("tunnel-controller")),
			Secrets:          secrets,
			Deployments:      kube.NewDeploymentAdapter(manager.GetClient(), manager.GetScheme(), controllers.TunnelOwnerLabel),
			Provider:         provider,
			Metrics:          recorder,
			CloudflaredImage: config.CloudflaredImage,
		}
		if err := reconciler.SetupWithManager(manager); err != nil {
			return fmt.Errorf("register Tunnel controller: %w", err)
		}
	}

	if config.EnableExposure {
		reconciler := &controllers.ExposureReconciler{
			Client:       manager.GetClient(),
			Clock:        clock,
			Recorder:     kube.NewEventRecorder(manager.GetEventRecorderFor("exposure-controller")),
			Secrets:      secrets,
			Services:     kube.NewServiceAdapter(manager.GetClient()),
			Provider:     provider,
			Metrics:      recorder,
			Installation: config.Installation(),
		}
		if err := reconciler.SetupWithManager(manager); err != nil {
			return fmt.Errorf("register Exposure controller: %w", err)
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
	dependencies := ControllerDependencies{Clock: kube.RealClock{}, Metrics: operatormetrics.NewPrometheus()}
	if config.FakeCloudflare {
		dependencies.Provider = seededFake()
	} else {
		dependencies.Provider = cloudflare.NewHTTP()
	}
	if err := RegisterControllers(manager, config, dependencies); err != nil {
		return err
	}
	if err := AddHealthChecks(manager); err != nil {
		return err
	}
	ctrl.Log.WithName("setup").Info("starting manager", "profile", config.Profile, "connected", config.Connected, "leaderElect", config.LeaderElection, "fakeCloudflare", config.FakeCloudflare)
	return manager.Start(ctx)
}

// seededFake returns the fake-CF adapter pre-seeded with the e2e fixture's
// policy set so a SIT run can resolve policies without a real account.
func seededFake() *cloudflare.Memory {
	fake := cloudflare.NewMemory()
	fake.Policies["atomi-admins"] = "policy-atomi-admins"
	return fake
}
