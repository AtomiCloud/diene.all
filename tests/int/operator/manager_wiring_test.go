package operator_test

import (
	"errors"
	"flag"
	"io"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/internal/operatorruntime"
)

func TestManagerWiringLegacyMultiController(t *testing.T) {
	t.Parallel()

	config := operatorruntime.Config{}
	flags := flag.NewFlagSet("manager-acceptance", flag.ContinueOnError)
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
	}))
	require.True(t, config.EnableCluster)
	require.True(t, config.EnablePlatform)
	require.True(t, config.EnableDependency)
	require.True(t, config.EnableTraffic)
	require.True(t, config.EnableWebhook)
	require.True(t, config.EnableCfDeploy)
	require.True(t, config.EnableProblem)

	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{},
	)
	require.ErrorIs(t, err, operatorruntime.ErrControllerBundleRequired)

	_, err = operatorruntime.BuildBundles(
		operatorruntime.Config{},
		operatorruntime.CredentialSet{
			Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "unexpected"},
		},
	)
	require.ErrorIs(t, err, operatorruntime.ErrCredentialOutsideEnabledSet)

	err = operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Cluster: &operatorruntime.ClusterBundle{
					ProviderAPI: testProviderDoor{kind: "wrong-kind"},
				},
			},
		},
	)
	require.ErrorIs(t, err, operatorruntime.ErrControllerBundleRequired)
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
	require.Empty(t, malformed.ActualKind)
	require.NotContains(t, err.Error(), foreignDoor.Kind())
}

func TestManagerWiringRejectsWrongKindCustomDoor(t *testing.T) {
	t.Parallel()

	// A hostile or misconfigured direct-injected door may return sensitive
	// provider material from Kind(). That untrusted value must never be retained
	// in the returned error metadata nor formatted into its string, while the
	// fixed controller/door/reason and the errors.Is category stay exact.
	const sensitiveKindValue = "account=AKIA-live-do-not-expose"

	err := operatorruntime.RegisterControllers(
		nil,
		operatorruntime.Config{EnableCluster: true},
		operatorruntime.ControllerDependencies{
			Bundles: operatorruntime.Bundles{
				Cluster: &operatorruntime.ClusterBundle{
					ProviderAPI: testProviderDoor{kind: sensitiveKindValue},
				},
			},
		},
	)
	malformed := assertMalformedBundle(t, err, "cluster", "provider-api", "has the wrong kind")
	require.Empty(t, malformed.ActualKind)
	require.NotContains(t, err.Error(), sensitiveKindValue)
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
