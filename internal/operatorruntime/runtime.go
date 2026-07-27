// Package operatorruntime owns the manager's configuration and controller wiring.
package operatorruntime

import (
	"context"
	"flag"
	"fmt"
	"strconv"

	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	metricsfilters "sigs.k8s.io/controller-runtime/pkg/metrics/filters"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/kube"
	operatormetrics "github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
	apifleet "github.com/AtomiCloud/diene.fleet-operator/api/fleet/v1alpha1"
	apiproblems "github.com/AtomiCloud/diene.fleet-operator/api/problems/v1alpha1"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/brake"
)

const leaderElectionID = "fleet-operator.diene.atomi.cloud"

const (
	envClusterProvider     = "FLEET_OPERATOR_CLUSTER_PROVIDER_API"
	envPlatformInfisical   = "FLEET_OPERATOR_PLATFORM_INFISICAL_ADMIN"
	envPlatformGitHub      = "FLEET_OPERATOR_PLATFORM_GITHUB_ORG_READ"
	envPlatformFleetRepo   = "FLEET_OPERATOR_PLATFORM_FLEET_REPO_WRITE"
	envDependencyVendors   = "FLEET_OPERATOR_DEPENDENCY_VENDOR_ENGINE"
	envDependencyBroker    = "FLEET_OPERATOR_DEPENDENCY_BROKER_TOKEN"
	envDependencyTigris    = "FLEET_OPERATOR_DEPENDENCY_NATIVE_TIGRIS_KEY"
	envDependencySeed      = "FLEET_OPERATOR_DEPENDENCY_READ_ONLY_SEED"
	envTrafficRoute53      = "FLEET_OPERATOR_TRAFFIC_ROUTE53"
	envTrafficCloudflare   = "FLEET_OPERATOR_TRAFFIC_CLOUDFLARE_DNS"
	envTrafficPublisher    = "FLEET_OPERATOR_TRAFFIC_EDGE_PUBLISHER"
	envWebhookManagement   = "FLEET_OPERATOR_WEBHOOK_MERCURY_MANAGEMENT"
	envWebhookLandscapeKV  = "FLEET_OPERATOR_WEBHOOK_LANDSCAPE_MERCURY_KV"
	envCfDeployWorkers     = "FLEET_OPERATOR_CF_DEPLOY_CLOUDFLARE_WORKERS"
	envBroadInfisicalWrite = "FLEET_OPERATOR_INFISICAL_WRITE"
	envBroadT4Root         = "FLEET_OPERATOR_T4_ROOT_PATH"
)

// Config is the manager configuration populated by its real command-line flags.
type Config struct {
	EnableCluster                   bool
	EnablePlatform                  bool
	EnableDependency                bool
	EnableTraffic                   bool
	EnableWebhook                   bool
	EnableCfDeploy                  bool
	EnableProblem                   bool
	Observe                         bool
	MetricsAddress                  string
	HealthAddress                   string
	LeaderElection                  bool
	BlastBrakeCap                   int
	TrafficCapPercent               int
	DependencyDestructiveCapPerTick int
	Platform                        string
	Landscape                       string
	LedgerEndpoint                  string
	LedgerBucket                    string
	LedgerSecure                    bool
	LedgerAccessKey                 string
	LedgerSecretKey                 string
}

// DefaultConfig returns production-safe defaults, including leader election and secured metrics.
func DefaultConfig(getenv func(string) string) Config {
	ledgerBucket := getenv("LEDGER_BUCKET")
	if ledgerBucket == "" {
		ledgerBucket = "fleet-operator-ledger"
	}
	return Config{
		MetricsAddress:                  ":8443",
		HealthAddress:                   ":8081",
		LeaderElection:                  true,
		BlastBrakeCap:                   20,
		TrafficCapPercent:               brake.DefaultTrafficCapPercent,
		DependencyDestructiveCapPerTick: brake.DefaultDependencyCapPerTick,
		Platform:                        "diene",
		Landscape:                       "lapras",
		LedgerEndpoint:                  getenv("LEDGER_ENDPOINT"),
		LedgerBucket:                    ledgerBucket,
		LedgerSecure:                    getenv("LEDGER_SECURE") == "true",
		LedgerAccessKey:                 getenv("LEDGER_ACCESS_KEY"),
		LedgerSecretKey:                 getenv("LEDGER_SECRET_KEY"),
	}
}

// CredentialSetFromEnvironment reads the presence-only controller credential
// inventory. It does not parse, validate, or construct a client from any value;
// BuildBundles performs the deterministic enable-by-presence decision later.
func CredentialSetFromEnvironment(getenv func(string) string) CredentialSet {
	return CredentialSet{
		Cluster: ClusterCredentials{
			ProviderAPI: getenv(envClusterProvider),
		},
		Platform: PlatformCredentials{
			InfisicalAdmin: getenv(envPlatformInfisical),
			GitHubOrgRead:  getenv(envPlatformGitHub),
			FleetRepoWrite: getenv(envPlatformFleetRepo),
		},
		Dependency: DependencyCredentials{
			VendorEngine:    getenv(envDependencyVendors),
			BrokerToken:     getenv(envDependencyBroker),
			NativeTigrisKey: getenv(envDependencyTigris),
			ReadOnlySeed:    supplied(getenv(envDependencySeed)),
		},
		Traffic: TrafficCredentials{
			Route53:       getenv(envTrafficRoute53),
			CloudflareDNS: getenv(envTrafficCloudflare),
			EdgePublisher: getenv(envTrafficPublisher),
		},
		Webhook: WebhookCredentials{
			MercuryManagement:  getenv(envWebhookManagement),
			LandscapeMercuryKV: getenv(envWebhookLandscapeKV),
		},
		CfDeploy: CfDeployCredentials{
			CloudflareWorkers: getenv(envCfDeployWorkers),
		},
		InfisicalWrite: getenv(envBroadInfisicalWrite),
		T4RootPath:     getenv(envBroadT4Root),
	}
}

// BindFlags binds the manager's public runtime interface directly to config.
func BindFlags(flags *flag.FlagSet, config *Config) {
	flags.BoolVar(&config.EnableCluster, "enable-cluster", config.EnableCluster, "enable the cluster controller")
	flags.BoolVar(&config.EnablePlatform, "enable-platform", config.EnablePlatform, "enable the platform controller")
	flags.BoolVar(&config.EnableDependency, "enable-dependency", config.EnableDependency, "enable the dependency controller")
	flags.BoolVar(&config.EnableTraffic, "enable-traffic", config.EnableTraffic, "enable the traffic controller")
	flags.BoolVar(&config.EnableWebhook, "enable-webhook", config.EnableWebhook, "enable the webhook controller")
	flags.BoolVar(&config.EnableCfDeploy, "enable-cf-deploy", config.EnableCfDeploy, "enable the cf-deploy controller")
	flags.BoolVar(&config.EnableProblem, "enable-problem", config.EnableProblem, "enable the reserved Problem sub-component seam")
	flags.BoolVar(&config.Observe, "observe", config.Observe, "run in observe mode: compute and report the plan without writing")
	flags.StringVar(&config.MetricsAddress, "metrics-bind-address", config.MetricsAddress, "secured metrics endpoint address")
	flags.StringVar(&config.HealthAddress, "health-probe-bind-address", config.HealthAddress, "health/readiness probe address")
	flags.BoolVar(&config.LeaderElection, "leader-elect", config.LeaderElection, "enable leader election (on even for a single replica)")
	flags.Var(
		newMirroredIntValue(&config.BlastBrakeCap, &config.TrafficCapPercent),
		"blast-brake-cap",
		"legacy alias for --traffic-cap-percent",
	)
	flags.Var(
		newMirroredIntValue(&config.TrafficCapPercent, &config.BlastBrakeCap),
		"traffic-cap-percent",
		"traffic record-removal percentage-per-tick cap",
	)
	flags.IntVar(
		&config.DependencyDestructiveCapPerTick,
		"dependency-destructive-cap-per-tick",
		config.DependencyDestructiveCapPerTick,
		"dependency destructive-module cap per tick",
	)
	flags.StringVar(&config.Platform, "platform", config.Platform, "ledger platform coordinate")
	flags.StringVar(&config.Landscape, "landscape", config.Landscape, "ledger landscape coordinate")
	flags.StringVar(&config.LedgerEndpoint, "ledger-endpoint", config.LedgerEndpoint, "S3/MinIO ledger endpoint host:port")
	flags.StringVar(&config.LedgerBucket, "ledger-bucket", config.LedgerBucket, "ledger bucket name")
	flags.BoolVar(&config.LedgerSecure, "ledger-secure", config.LedgerSecure, "use TLS for the ledger endpoint")
}

type mirroredIntValue struct {
	primary *int
	mirror  *int
}

func newMirroredIntValue(primary, mirror *int) *mirroredIntValue {
	return &mirroredIntValue{primary: primary, mirror: mirror}
}

func (v *mirroredIntValue) String() string {
	return strconv.Itoa(*v.primary)
}

func (v *mirroredIntValue) Set(raw string) error {
	value, err := strconv.Atoi(raw)
	if err != nil {
		return fmt.Errorf("parse integer %q: %w", raw, err)
	}
	*v.primary = value
	*v.mirror = value
	return nil
}

func (v *mirroredIntValue) Get() any {
	return *v.primary
}

// ControllerDependencies contains replaceable runtime dependencies for registration tests.
type ControllerDependencies struct {
	Clock   kube.Clock
	Metrics operatormetrics.Recorder
	Bundles Bundles
}

// NewScheme returns the scheme used by both the production manager and fixtures.
func NewScheme() (*runtime.Scheme, error) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register client-go scheme: %w", err)
	}
	if err := apifleet.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register fleet scheme: %w", err)
	}
	if err := apiproblems.AddToScheme(scheme); err != nil {
		return nil, fmt.Errorf("register problems scheme: %w", err)
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
func RegisterControllers(_ ctrl.Manager, config Config, dependencies ControllerDependencies) error {
	if config.EnableProblem {
		return ErrProblemNotFolded
	}
	if config.EnableCluster {
		bundle := dependencies.Bundles.Cluster
		if bundle == nil {
			return &MissingBundleError{Controller: controllerCluster}
		}
		if err := validateRequiredDoor(controllerCluster, capClusterProviderAPI, bundle.ProviderAPI); err != nil {
			return err
		}
	}
	if config.EnablePlatform {
		bundle := dependencies.Bundles.Platform
		if bundle == nil {
			return &MissingBundleError{Controller: controllerPlatform}
		}
		for _, requirement := range []struct {
			kind string
			door ProviderDoor
		}{
			{kind: capPlatformInfisicalAdmin, door: bundle.InfisicalAdmin},
			{kind: capPlatformGitHubOrgRead, door: bundle.GitHubOrgRead},
			{kind: capPlatformFleetRepoWrite, door: bundle.FleetRepoWrite},
		} {
			if err := validateRequiredDoor(controllerPlatform, requirement.kind, requirement.door); err != nil {
				return err
			}
		}
	}
	if config.EnableDependency {
		bundle := dependencies.Bundles.Dependency
		if bundle == nil {
			return &MissingBundleError{Controller: controllerDependency}
		}
		for _, requirement := range []struct {
			kind string
			door ProviderDoor
		}{
			{kind: capDependencyVendorEngine, door: bundle.VendorEngine},
			{kind: capDependencyBrokerToken, door: bundle.BrokerToken},
			{kind: capDependencyNativeTigris, door: bundle.NativeTigrisKey},
			{kind: capDependencyReadOnlySeed, door: bundle.ReadOnlySeed},
		} {
			if err := validateOptionalDoor(controllerDependency, requirement.kind, requirement.door); err != nil {
				return err
			}
		}
	}
	if config.EnableTraffic {
		bundle := dependencies.Bundles.Traffic
		if bundle == nil {
			return &MissingBundleError{Controller: controllerTraffic}
		}
		for _, requirement := range []struct {
			kind string
			door ProviderDoor
		}{
			{kind: capTrafficRoute53, door: bundle.Route53},
			{kind: capTrafficCloudflareDNS, door: bundle.CloudflareDNS},
			{kind: capTrafficEdgePublisher, door: bundle.EdgePublisher},
		} {
			if err := validateRequiredDoor(controllerTraffic, requirement.kind, requirement.door); err != nil {
				return err
			}
		}
	}
	if config.EnableWebhook {
		bundle := dependencies.Bundles.Webhook
		if bundle == nil {
			return &MissingBundleError{Controller: controllerWebhook}
		}
		for _, requirement := range []struct {
			kind string
			door ProviderDoor
		}{
			{kind: capWebhookMercuryManagement, door: bundle.MercuryManagement},
			{kind: capWebhookLandscapeKV, door: bundle.LandscapeMercuryKV},
		} {
			if err := validateRequiredDoor(controllerWebhook, requirement.kind, requirement.door); err != nil {
				return err
			}
		}
	}
	if config.EnableCfDeploy {
		bundle := dependencies.Bundles.CfDeploy
		if bundle == nil {
			return &MissingBundleError{Controller: controllerCfDeploy}
		}
		if err := validateRequiredDoor(controllerCfDeploy, capCfDeployWorkers, bundle.CloudflareWorkers); err != nil {
			return err
		}
	}

	// Phase 2 intentionally stops at these six bundle-gated registration
	// seams. Phase 3 adds each real reconciler inside its matching branch.
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
	return StartWithCredentials(ctx, restConfig, config, CredentialSet{})
}

// StartWithCredentials constructs and runs the production manager with the
// explicit presence inventory supplied by the command composition root.
func StartWithCredentials(ctx context.Context, restConfig *rest.Config, config Config, credentials CredentialSet) error {
	dependencies, err := productionDependencies(ctx, config, credentials)
	if err != nil {
		return err
	}
	scheme, err := NewScheme()
	if err != nil {
		return err
	}
	manager, err := NewManager(restConfig, scheme, config)
	if err != nil {
		return fmt.Errorf("create manager: %w", err)
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

func productionDependencies(_ context.Context, config Config, credentials CredentialSet) (ControllerDependencies, error) {
	bundles, err := BuildBundles(config, credentials)
	if err != nil {
		return ControllerDependencies{}, err
	}
	dependencies := ControllerDependencies{
		Clock:   kube.RealClock{},
		Metrics: operatormetrics.NewPrometheus(),
		Bundles: bundles,
	}
	return dependencies, nil
}
