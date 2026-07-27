package operator_test

import (
	"context"
	"errors"
	"flag"
	"io"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/v1alpha1"
	"github.com/AtomiCloud/diene.fleet-operator/internal/operatorruntime"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
)

func TestManagerWiringLegacyMultiController(t *testing.T) {
	config := operatorruntime.Config{}
	flags := flag.NewFlagSet("manager-acceptance", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	operatorruntime.BindFlags(flags, &config)
	require.NoError(t, flags.Parse([]string{
		"--enable-note=true",
		"--enable-journal=true",
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address=0",
		"--blast-brake-cap=20",
		"--dependency-destructive-cap-per-tick=3",
		"--platform=diene",
		"--landscape=lapras",
	}))
	require.True(t, config.EnableNote)
	require.True(t, config.EnableJournal)
	require.False(t, config.LeaderElection)
	require.Equal(t, 20, config.TrafficCapPercent)
	require.Equal(t, 3, config.DependencyDestructiveCapPerTick)

	manager, err := operatorruntime.NewManager(restConfig, testScheme, config)
	require.NoError(t, err)
	noteLedger := ledger.NewService(newFakeLedgerStore())
	require.NoError(t, operatorruntime.RegisterControllers(manager, config, operatorruntime.ControllerDependencies{
		Clock:      fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Metrics:    metrics.NewPrometheus(),
		NoteLedger: &noteLedger,
	}))

	managerContext, stopManager := context.WithCancel(context.Background())
	managerDone := make(chan error, 1)
	go func() {
		managerDone <- manager.Start(managerContext)
	}()
	t.Cleanup(func() {
		stopManager()
		require.NoError(t, <-managerDone)
	})

	cacheContext, stopCacheWait := context.WithTimeout(managerContext, 10*time.Second)
	defer stopCacheWait()
	require.True(t, manager.GetCache().WaitForCacheSync(cacheContext))

	note := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: "manager-note", Namespace: "default"},
		Spec: apiv1alpha1.NoteSpec{
			Title:    "Manager Note",
			Body:     "converged through enabled registration",
			Category: "work",
			Replicas: 1,
		},
	}
	journal := &apiv1alpha1.Journal{
		ObjectMeta: metav1.ObjectMeta{Name: "manager-journal", Namespace: "default"},
		Spec:       apiv1alpha1.JournalSpec{Message: "converged independently"},
	}
	require.NoError(t, k8sClient.Create(context.Background(), note))
	require.NoError(t, k8sClient.Create(context.Background(), journal))

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Note
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(note), &current); err != nil {
			return false
		}
		ready := apimeta.FindStatusCondition(current.Status.Conditions, plan.TypeReady)
		return ready != nil && ready.Status == metav1.ConditionTrue && current.Status.OwnedConfigMaps == 1
	}, 15*time.Second, 100*time.Millisecond, "enabled Note controller did not converge")

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Journal
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(journal), &current); err != nil {
			return false
		}
		ready := apimeta.FindStatusCondition(current.Status.Conditions, plan.TypeReady)
		return ready != nil && ready.Status == metav1.ConditionTrue
	}, 15*time.Second, 100*time.Millisecond, "enabled Journal controller did not converge")

	var owned corev1.ConfigMapList
	require.NoError(t, k8sClient.List(
		context.Background(), &owned,
		client.InNamespace("default"),
		client.MatchingLabels{controllers.NoteOwnerLabel: note.Name},
	))
	require.Len(t, owned.Items, 1)
}

func TestManagerWiringRealControllerFlagsAndGlobalObserve(t *testing.T) {
	t.Parallel()

	config := operatorruntime.Config{}
	flags := flag.NewFlagSet("manager-real-flags", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	operatorruntime.BindFlags(flags, &config)
	require.NoError(t, flags.Parse([]string{
		"--enable-cluster=true",
		"--enable-platform=true",
		"--enable-dependency=true",
		"--enable-traffic=true",
		"--enable-webhook=true",
		"--enable-cf-deploy=true",
		"--enable-problem=true",
		"--observe=true",
	}))

	require.True(t, config.EnableCluster)
	require.True(t, config.EnablePlatform)
	require.True(t, config.EnableDependency)
	require.True(t, config.EnableTraffic)
	require.True(t, config.EnableWebhook)
	require.True(t, config.EnableCfDeploy)
	require.True(t, config.EnableProblem)
	require.True(t, config.Observe)
}

func TestManagerWiringBrakeFlagAliases(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		arg  string
		want int
	}{
		{name: "new traffic flag mirrors legacy field", arg: "--traffic-cap-percent=27", want: 27},
		{name: "legacy flag mirrors new traffic field", arg: "--blast-brake-cap=18", want: 18},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			config := operatorruntime.Config{BlastBrakeCap: 20, TrafficCapPercent: 20}
			flags := flag.NewFlagSet("manager-brake-flags", flag.ContinueOnError)
			flags.SetOutput(io.Discard)
			operatorruntime.BindFlags(flags, &config)

			require.NoError(t, flags.Parse([]string{test.arg}))
			require.Equal(t, test.want, config.BlastBrakeCap)
			require.Equal(t, test.want, config.TrafficCapPercent)
		})
	}
}

func TestManagerWiringEnabledControllersRequireOwnBundle(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		controller  string
		config      operatorruntime.Config
		credentials operatorruntime.CredentialSet
	}{
		{
			name: "cluster", controller: "cluster",
			config:      operatorruntime.Config{EnableCluster: true},
			credentials: operatorruntime.CredentialSet{Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "present"}},
		},
		{
			name: "platform", controller: "platform",
			config: operatorruntime.Config{EnablePlatform: true},
			credentials: operatorruntime.CredentialSet{Platform: operatorruntime.PlatformCredentials{
				InfisicalAdmin: "present", GitHubOrgRead: "present", FleetRepoWrite: "present",
			}},
		},
		{
			name: "dependency", controller: "dependency",
			config: operatorruntime.Config{EnableDependency: true},
		},
		{
			name: "traffic", controller: "traffic",
			config: operatorruntime.Config{EnableTraffic: true},
			credentials: operatorruntime.CredentialSet{Traffic: operatorruntime.TrafficCredentials{
				Route53: "present", CloudflareDNS: "present", EdgePublisher: "present",
			}},
		},
		{
			name: "webhook", controller: "webhook",
			config: operatorruntime.Config{EnableWebhook: true},
			credentials: operatorruntime.CredentialSet{Webhook: operatorruntime.WebhookCredentials{
				MercuryManagement: "present", LandscapeMercuryKV: "present",
			}},
		},
		{
			name: "cf-deploy", controller: "cf-deploy",
			config:      operatorruntime.Config{EnableCfDeploy: true},
			credentials: operatorruntime.CredentialSet{CfDeploy: operatorruntime.CfDeployCredentials{CloudflareWorkers: "present"}},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			err := operatorruntime.RegisterControllers(nil, test.config, operatorruntime.ControllerDependencies{})
			require.ErrorIs(t, err, operatorruntime.ErrControllerBundleRequired)
			var missing *operatorruntime.MissingBundleError
			require.ErrorAs(t, err, &missing)
			require.Equal(t, test.controller, missing.Controller)

			bundles, err := operatorruntime.BuildBundles(test.config, test.credentials)
			require.NoError(t, err)
			require.NoError(t, operatorruntime.RegisterControllers(nil, test.config, operatorruntime.ControllerDependencies{
				Bundles: bundles,
			}))
		})
	}
}

func TestManagerWiringFullPrimordialNoOpSeams(t *testing.T) {
	t.Parallel()

	config := fullControllerConfig()
	config.Observe = true
	bundles, err := operatorruntime.BuildBundles(config, fullCredentialSet())
	require.NoError(t, err)
	require.NoError(t, operatorruntime.RegisterControllers(nil, config, operatorruntime.ControllerDependencies{
		Bundles: bundles,
	}))
}

func TestManagerWiringRejectsMalformedDependencyBundle(t *testing.T) {
	t.Parallel()

	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableDependency: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{Dependency: &operatorruntime.DependencyBundle{}},
		},
	)
	malformed := assertMalformedBundle(t, err, "dependency", "vendor-engine", "is nil")
	require.Empty(t, malformed.ActualKind)
}

func TestManagerWiringRejectsCrossControllerDoorSubstitution(t *testing.T) {
	t.Parallel()

	clusterBundles, err := operatorruntime.BuildBundles(
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.CredentialSet{
			Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "present"},
		},
	)
	require.NoError(t, err)
	foreignDoor := clusterBundles.Cluster.ProviderAPI

	err = operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableDependency: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Dependency: &operatorruntime.DependencyBundle{
					VendorEngine:    foreignDoor,
					BrokerToken:     foreignDoor,
					NativeTigrisKey: foreignDoor,
					ReadOnlySeed:    foreignDoor,
				},
			},
		},
	)
	malformed := assertMalformedBundle(t, err, "dependency", "vendor-engine", "has the wrong kind")
	require.Equal(t, "provider-api", malformed.ActualKind)
}

func TestManagerWiringRejectsWrongKindCustomDoor(t *testing.T) {
	t.Parallel()

	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Cluster: &operatorruntime.ClusterBundle{
					ProviderAPI: testProviderDoor{kind: "custom-wrong-kind"},
				},
			},
		},
	)
	malformed := assertMalformedBundle(t, err, "cluster", "provider-api", "has the wrong kind")
	require.Equal(t, "custom-wrong-kind", malformed.ActualKind)
}

func TestManagerWiringRejectsUnavailableRequiredDoor(t *testing.T) {
	t.Parallel()

	providerError := errors.New("provider error containing a credential value")
	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Cluster: &operatorruntime.ClusterBundle{
					ProviderAPI: testProviderDoor{kind: "provider-api", available: providerError},
				},
			},
		},
	)
	malformed := assertMalformedBundle(t, err, "cluster", "provider-api", "is unavailable")
	require.Empty(t, malformed.ActualKind)
	require.NotContains(t, err.Error(), providerError.Error())
	require.NotErrorIs(t, err, providerError)
}

func TestManagerWiringRejectsTypedNilDoor(t *testing.T) {
	t.Parallel()

	var typedNil *typedNilProviderDoor
	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Cluster: &operatorruntime.ClusterBundle{ProviderAPI: typedNil},
			},
		},
	)
	malformed := assertMalformedBundle(t, err, "cluster", "provider-api", "contains a typed nil")
	require.Empty(t, malformed.ActualKind)
}

func TestManagerWiringRejectsUnavailableCustomDependencyDoor(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		available error
	}{
		{name: "provider error", available: errors.New("provider error containing a credential value")},
		{name: "fake absent refusal", available: operatorruntime.ErrDoorAbsent},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			config := operatorruntime.Config{EnableDependency: true}
			bundles, err := operatorruntime.BuildBundles(config, operatorruntime.CredentialSet{})
			require.NoError(t, err)
			bundles.Dependency.VendorEngine = testProviderDoor{
				kind:      "vendor-engine",
				available: test.available,
			}

			err = operatorruntime.RegisterControllers(
				nil,
				config,
				operatorruntime.ControllerDependencies{Bundles: bundles},
			)
			malformed := assertMalformedBundle(
				t,
				err,
				"dependency",
				"vendor-engine",
				"is unavailable without typed absence",
			)
			require.Empty(t, malformed.ActualKind)
			require.NotContains(t, err.Error(), test.available.Error())
			require.NotErrorIs(t, err, test.available)
		})
	}
}

func TestManagerWiringAcceptsUnavailableDependencyDoors(t *testing.T) {
	t.Parallel()

	config := operatorruntime.Config{EnableDependency: true}
	bundles, err := operatorruntime.BuildBundles(config, operatorruntime.CredentialSet{})
	require.NoError(t, err)
	for _, door := range []operatorruntime.ProviderDoor{
		bundles.Dependency.VendorEngine,
		bundles.Dependency.BrokerToken,
		bundles.Dependency.NativeTigrisKey,
		bundles.Dependency.ReadOnlySeed,
	} {
		require.ErrorIs(t, door.Available(), operatorruntime.ErrDoorAbsent)
	}
	require.NoError(t, operatorruntime.RegisterControllers(
		nil,
		config,
		operatorruntime.ControllerDependencies{Bundles: bundles},
	))
}

func TestManagerWiringProblemReservedSeam(t *testing.T) {
	t.Parallel()

	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableProblem: true},
		operatorruntime.ControllerDependencies{},
	)
	require.ErrorIs(t, err, operatorruntime.ErrProblemNotFolded)
	require.EqualError(t, err, "problem sub-component not yet folded")
}

type testProviderDoor struct {
	kind      string
	available error
}

func (d testProviderDoor) Kind() string     { return d.kind }
func (d testProviderDoor) Available() error { return d.available }

type typedNilProviderDoor struct{}

func (*typedNilProviderDoor) Kind() string     { return "provider-api" }
func (*typedNilProviderDoor) Available() error { return nil }

func assertMalformedBundle(
	t *testing.T,
	err error,
	controller string,
	door string,
	reason string,
) *operatorruntime.MalformedBundleError {
	t.Helper()
	require.ErrorIs(t, err, operatorruntime.ErrControllerBundleRequired)
	var malformed *operatorruntime.MalformedBundleError
	require.ErrorAs(t, err, &malformed)
	require.Equal(t, controller, malformed.Controller)
	require.Equal(t, door, malformed.Door)
	require.Equal(t, reason, malformed.Reason)
	return malformed
}
