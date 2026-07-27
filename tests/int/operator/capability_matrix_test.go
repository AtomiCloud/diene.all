package operator_test

import (
	"fmt"
	"reflect"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/internal/operatorruntime"
)

func TestCapabilityMatrixRow1MissingRequiredCredentials(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		controller string
		credential string
		omit       func(*operatorruntime.CredentialSet)
	}{
		{
			name: "cluster provider API", controller: "cluster", credential: "provider-api",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Cluster.ProviderAPI = "" },
		},
		{
			name: "platform Infisical admin", controller: "platform", credential: "infisical-admin",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.InfisicalAdmin = "" },
		},
		{
			name: "platform GitHub org read", controller: "platform", credential: "github-org-read",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.GitHubOrgRead = "" },
		},
		{
			name: "platform fleet repo write", controller: "platform", credential: "fleet-repo-write",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.FleetRepoWrite = "" },
		},
		{
			name: "traffic Route53", controller: "traffic", credential: "route53",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.Route53 = "" },
		},
		{
			name: "traffic Cloudflare DNS", controller: "traffic", credential: "cloudflare-dns",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.CloudflareDNS = "" },
		},
		{
			name: "traffic edge publisher", controller: "traffic", credential: "edge-publisher",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.EdgePublisher = "" },
		},
		{
			name: "webhook mercury management", controller: "webhook", credential: "mercury-management",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Webhook.MercuryManagement = "" },
		},
		{
			name: "webhook landscape mercury KV", controller: "webhook", credential: "landscape-mercury-kv",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.Webhook.LandscapeMercuryKV = "" },
		},
		{
			name: "cf-deploy workers", controller: "cf-deploy", credential: "cloudflare-workers",
			omit: func(credentials *operatorruntime.CredentialSet) { credentials.CfDeploy.CloudflareWorkers = "" },
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			credentials := fullCredentialSet()
			test.omit(&credentials)

			bundles, err := operatorruntime.BuildBundles(fullControllerConfig(), credentials)

			require.Equal(t, operatorruntime.Bundles{}, bundles)
			require.ErrorIs(t, err, operatorruntime.ErrCredentialRequired)
			var missing *operatorruntime.MissingCredentialError
			require.ErrorAs(t, err, &missing)
			require.Equal(t, test.controller, missing.Controller)
			require.Equal(t, test.credential, missing.Credential)
		})
	}
}

func TestCapabilityMatrixRow2CredentialsForDisabledControllers(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		controller string
		credential string
		supply     func(*operatorruntime.CredentialSet)
	}{
		{
			name: "cluster provider API", controller: "cluster", credential: "provider-api",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Cluster.ProviderAPI = "present" },
		},
		{
			name: "platform Infisical admin", controller: "platform", credential: "infisical-admin",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.InfisicalAdmin = "present" },
		},
		{
			name: "platform GitHub org read", controller: "platform", credential: "github-org-read",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.GitHubOrgRead = "present" },
		},
		{
			name: "platform fleet repo write", controller: "platform", credential: "fleet-repo-write",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.FleetRepoWrite = "present" },
		},
		{
			name: "dependency vendor engine", controller: "dependency", credential: "vendor-engine",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Dependency.VendorEngine = "present" },
		},
		{
			name: "dependency broker token", controller: "dependency", credential: "broker-token",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Dependency.BrokerToken = "present" },
		},
		{
			name: "dependency native Tigris", controller: "dependency", credential: "native-tigris-key",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Dependency.NativeTigrisKey = "present" },
		},
		{
			name: "dependency read-only seed", controller: "dependency", credential: "read-only-seed",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Dependency.ReadOnlySeed = true },
		},
		{
			name: "traffic Route53", controller: "traffic", credential: "route53",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.Route53 = "present" },
		},
		{
			name: "traffic Cloudflare DNS", controller: "traffic", credential: "cloudflare-dns",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.CloudflareDNS = "present" },
		},
		{
			name: "traffic edge publisher", controller: "traffic", credential: "edge-publisher",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.EdgePublisher = "present" },
		},
		{
			name: "webhook mercury management", controller: "webhook", credential: "mercury-management",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Webhook.MercuryManagement = "present" },
		},
		{
			name: "webhook landscape mercury KV", controller: "webhook", credential: "landscape-mercury-kv",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Webhook.LandscapeMercuryKV = "present" },
		},
		{
			name: "cf-deploy workers", controller: "cf-deploy", credential: "cloudflare-workers",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.CfDeploy.CloudflareWorkers = "present" },
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			var credentials operatorruntime.CredentialSet
			test.supply(&credentials)

			bundles, err := operatorruntime.BuildBundles(operatorruntime.Config{}, credentials)

			require.Equal(t, operatorruntime.Bundles{}, bundles)
			assertCredentialOutsideEnabledSet(t, err, test.controller, test.credential)
		})
	}
}

func TestCapabilityMatrixRow3ProblemReservedSeam(t *testing.T) {
	t.Parallel()

	bundles, err := operatorruntime.BuildBundles(
		operatorruntime.Config{EnableProblem: true},
		operatorruntime.CredentialSet{},
	)

	require.Equal(t, operatorruntime.Bundles{}, bundles)
	require.ErrorIs(t, err, operatorruntime.ErrProblemNotFolded)
	require.EqualError(t, err, "problem sub-component not yet folded")
}

func TestCapabilityMatrixRow4GardenAllowsEveryDependencySubset(t *testing.T) {
	t.Parallel()

	for mask := 0; mask < 16; mask++ {
		t.Run(fmt.Sprintf("doors-%04b", mask), func(t *testing.T) {
			t.Parallel()
			credentials := operatorruntime.CredentialSet{
				Dependency: operatorruntime.DependencyCredentials{
					VendorEngine:    optionalValue(mask&1 != 0),
					BrokerToken:     optionalValue(mask&2 != 0),
					NativeTigrisKey: optionalValue(mask&4 != 0),
					ReadOnlySeed:    mask&8 != 0,
				},
			}

			bundles, err := operatorruntime.BuildBundles(
				operatorruntime.Config{EnableDependency: true},
				credentials,
			)

			require.NoError(t, err)
			require.NotNil(t, bundles.Dependency)
			assertDoorAvailability(t, bundles.Dependency.VendorEngine, mask&1 != 0)
			assertDoorAvailability(t, bundles.Dependency.BrokerToken, mask&2 != 0)
			assertDoorAvailability(t, bundles.Dependency.NativeTigrisKey, mask&4 != 0)
			assertDoorAvailability(t, bundles.Dependency.ReadOnlySeed, mask&8 != 0)
		})
	}
}

func TestCapabilityMatrixRow5RotomAbsolZeroCredentials(t *testing.T) {
	t.Parallel()

	bundles, err := operatorruntime.BuildBundles(
		operatorruntime.Config{EnableDependency: true},
		operatorruntime.CredentialSet{},
	)

	require.NoError(t, err)
	require.NotNil(t, bundles.Dependency)
	for _, door := range []operatorruntime.ProviderDoor{
		bundles.Dependency.VendorEngine,
		bundles.Dependency.BrokerToken,
		bundles.Dependency.NativeTigrisKey,
		bundles.Dependency.ReadOnlySeed,
	} {
		require.NotNil(t, door)
		require.ErrorIs(t, door.Available(), operatorruntime.ErrDoorAbsent)
		var absent *operatorruntime.AbsentDoor
		require.ErrorAs(t, door.Available(), &absent)
		require.Equal(t, door.Kind(), absent.Kind())
	}
}

func TestCapabilityMatrixRow6GardenRejectsPrimordialCredentials(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		controller string
		credential string
		supply     func(*operatorruntime.CredentialSet)
	}{
		{
			name: "Infisical write", controller: "dependency", credential: "infisical-write",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.InfisicalWrite = "present" },
		},
		{
			name: "T4 root path", controller: "primordial", credential: "t4-root-path",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.T4RootPath = "present" },
		},
		{
			name: "cluster group", controller: "cluster", credential: "provider-api",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Cluster.ProviderAPI = "present" },
		},
		{
			name: "platform group", controller: "platform", credential: "infisical-admin",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Platform.InfisicalAdmin = "present" },
		},
		{
			name: "traffic group", controller: "traffic", credential: "route53",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Traffic.Route53 = "present" },
		},
		{
			name: "webhook group", controller: "webhook", credential: "mercury-management",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.Webhook.MercuryManagement = "present" },
		},
		{
			name: "cf-deploy group", controller: "cf-deploy", credential: "cloudflare-workers",
			supply: func(credentials *operatorruntime.CredentialSet) { credentials.CfDeploy.CloudflareWorkers = "present" },
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			var credentials operatorruntime.CredentialSet
			test.supply(&credentials)

			bundles, err := operatorruntime.BuildBundles(
				operatorruntime.Config{EnableDependency: true},
				credentials,
			)

			require.Equal(t, operatorruntime.Bundles{}, bundles)
			assertCredentialOutsideEnabledSet(t, err, test.controller, test.credential)
		})
	}
}

func TestCapabilityMatrixRow7FullPrimordialIsolation(t *testing.T) {
	t.Parallel()

	bundles, err := operatorruntime.BuildBundles(fullControllerConfig(), fullCredentialSet())

	require.NoError(t, err)
	require.NotNil(t, bundles.Cluster)
	require.NotNil(t, bundles.Platform)
	require.NotNil(t, bundles.Dependency)
	require.NotNil(t, bundles.Traffic)
	require.NotNil(t, bundles.Webhook)
	require.NotNil(t, bundles.CfDeploy)
	assertNarrowBundleCompileShapes(bundles)

	doors := []operatorruntime.ProviderDoor{
		bundles.Cluster.ProviderAPI,
		bundles.Platform.InfisicalAdmin,
		bundles.Platform.GitHubOrgRead,
		bundles.Platform.FleetRepoWrite,
		bundles.Dependency.VendorEngine,
		bundles.Dependency.BrokerToken,
		bundles.Dependency.NativeTigrisKey,
		bundles.Dependency.ReadOnlySeed,
		bundles.Traffic.Route53,
		bundles.Traffic.CloudflareDNS,
		bundles.Traffic.EdgePublisher,
		bundles.Webhook.MercuryManagement,
		bundles.Webhook.LandscapeMercuryKV,
		bundles.CfDeploy.CloudflareWorkers,
	}
	seen := make(map[uintptr]string, len(doors))
	for _, door := range doors {
		require.NoError(t, door.Available())
		address := reflect.ValueOf(door).Pointer()
		require.NotContains(t, seen, address, "%s shares a door instance with %s", door.Kind(), seen[address])
		seen[address] = door.Kind()
	}
}

func TestCapabilityMatrixRow8ObserveParity(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		config      operatorruntime.Config
		credentials operatorruntime.CredentialSet
	}{
		{name: "nothing enabled"},
		{name: "Garden zero credential", config: operatorruntime.Config{EnableDependency: true}},
		{name: "full Primordial", config: fullControllerConfig(), credentials: fullCredentialSet()},
		{name: "enabled missing", config: operatorruntime.Config{EnableCluster: true}},
		{
			name: "disabled supplied",
			credentials: operatorruntime.CredentialSet{
				Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "present"},
			},
		},
		{name: "reserved problem", config: operatorruntime.Config{EnableProblem: true}},
		{
			name:        "forbidden root",
			config:      operatorruntime.Config{EnableDependency: true},
			credentials: operatorruntime.CredentialSet{T4RootPath: "present"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			activeBundles, activeErr := operatorruntime.BuildBundles(test.config, test.credentials)
			observeConfig := test.config
			observeConfig.Observe = true
			observeBundles, observeErr := operatorruntime.BuildBundles(observeConfig, test.credentials)

			require.Equal(t, bundleSignature(activeBundles), bundleSignature(observeBundles))
			require.Equal(t, errorSignature(activeErr), errorSignature(observeErr))
		})
	}
}

func TestCapabilityMatrixDistinctBundlesDoNotShareCredentialObjects(t *testing.T) {
	t.Parallel()

	credentials := operatorruntime.CredentialSet{
		Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "same-reference"},
		Traffic: operatorruntime.TrafficCredentials{
			Route53:       "same-reference",
			CloudflareDNS: "same-reference",
			EdgePublisher: "same-reference",
		},
	}
	bundles, err := operatorruntime.BuildBundles(
		operatorruntime.Config{EnableCluster: true, EnableTraffic: true},
		credentials,
	)
	require.NoError(t, err)
	require.Nil(t, bundles.Platform)
	require.Nil(t, bundles.Dependency)
	require.Nil(t, bundles.Webhook)
	require.Nil(t, bundles.CfDeploy)

	doors := []operatorruntime.ProviderDoor{
		bundles.Cluster.ProviderAPI,
		bundles.Traffic.Route53,
		bundles.Traffic.CloudflareDNS,
		bundles.Traffic.EdgePublisher,
	}
	addresses := make(map[uintptr]struct{}, len(doors))
	for _, door := range doors {
		address := reflect.ValueOf(door).Pointer()
		require.NotContains(t, addresses, address)
		addresses[address] = struct{}{}
	}
}

func TestCapabilityMatrixGardenDependencyCompileShape(t *testing.T) {
	t.Parallel()

	bundles, err := operatorruntime.BuildBundles(
		operatorruntime.Config{EnableDependency: true},
		operatorruntime.CredentialSet{},
	)
	require.NoError(t, err)

	// This assignment is a compile-time assertion of the exact Garden shape.
	// Adding an Infisical-write, T4-root, or cross-controller field to
	// DependencyBundle makes the external black-box test stop compiling.
	acceptGardenDependencyShape(*bundles.Dependency)
	typeOfBundle := reflect.TypeOf(*bundles.Dependency)
	_, hasInfisicalWrite := typeOfBundle.FieldByName("InfisicalWrite")
	_, hasT4Root := typeOfBundle.FieldByName("T4RootPath")
	require.False(t, hasInfisicalWrite)
	require.False(t, hasT4Root)
}

func fullControllerConfig() operatorruntime.Config {
	return operatorruntime.Config{
		EnableCluster:    true,
		EnablePlatform:   true,
		EnableDependency: true,
		EnableTraffic:    true,
		EnableWebhook:    true,
		EnableCfDeploy:   true,
	}
}

func fullCredentialSet() operatorruntime.CredentialSet {
	return operatorruntime.CredentialSet{
		Cluster: operatorruntime.ClusterCredentials{ProviderAPI: "cluster-provider"},
		Platform: operatorruntime.PlatformCredentials{
			InfisicalAdmin: "platform-infisical",
			GitHubOrgRead:  "platform-github",
			FleetRepoWrite: "platform-fleet-repo",
		},
		Dependency: operatorruntime.DependencyCredentials{
			VendorEngine:    "dependency-vendors",
			BrokerToken:     "dependency-broker",
			NativeTigrisKey: "dependency-tigris",
			ReadOnlySeed:    true,
		},
		Traffic: operatorruntime.TrafficCredentials{
			Route53:       "traffic-route53",
			CloudflareDNS: "traffic-cloudflare",
			EdgePublisher: "traffic-edge",
		},
		Webhook: operatorruntime.WebhookCredentials{
			MercuryManagement:  "webhook-management",
			LandscapeMercuryKV: "webhook-kv",
		},
		CfDeploy: operatorruntime.CfDeployCredentials{CloudflareWorkers: "cf-deploy-workers"},
	}
}

func assertCredentialOutsideEnabledSet(t *testing.T, err error, controller, credential string) {
	t.Helper()
	require.ErrorIs(t, err, operatorruntime.ErrCredentialOutsideEnabledSet)
	var outside *operatorruntime.CredentialOutsideEnabledSetError
	require.ErrorAs(t, err, &outside)
	require.Equal(t, controller, outside.Controller)
	require.Equal(t, credential, outside.Credential)
}

func assertDoorAvailability(t *testing.T, door operatorruntime.ProviderDoor, available bool) {
	t.Helper()
	require.NotNil(t, door)
	if available {
		require.NoError(t, door.Available())
		return
	}
	require.ErrorIs(t, door.Available(), operatorruntime.ErrDoorAbsent)
}

func optionalValue(present bool) string {
	if present {
		return "present"
	}
	return ""
}

func errorSignature(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func bundleSignature(bundles operatorruntime.Bundles) []string {
	var signature []string
	appendDoor := func(controller string, door operatorruntime.ProviderDoor) {
		state := "available"
		if err := door.Available(); err != nil {
			state = err.Error()
		}
		signature = append(signature, controller+":"+door.Kind()+":"+state)
	}
	if bundles.Cluster != nil {
		appendDoor("cluster", bundles.Cluster.ProviderAPI)
	}
	if bundles.Platform != nil {
		appendDoor("platform", bundles.Platform.InfisicalAdmin)
		appendDoor("platform", bundles.Platform.GitHubOrgRead)
		appendDoor("platform", bundles.Platform.FleetRepoWrite)
	}
	if bundles.Dependency != nil {
		appendDoor("dependency", bundles.Dependency.VendorEngine)
		appendDoor("dependency", bundles.Dependency.BrokerToken)
		appendDoor("dependency", bundles.Dependency.NativeTigrisKey)
		appendDoor("dependency", bundles.Dependency.ReadOnlySeed)
	}
	if bundles.Traffic != nil {
		appendDoor("traffic", bundles.Traffic.Route53)
		appendDoor("traffic", bundles.Traffic.CloudflareDNS)
		appendDoor("traffic", bundles.Traffic.EdgePublisher)
	}
	if bundles.Webhook != nil {
		appendDoor("webhook", bundles.Webhook.MercuryManagement)
		appendDoor("webhook", bundles.Webhook.LandscapeMercuryKV)
	}
	if bundles.CfDeploy != nil {
		appendDoor("cf-deploy", bundles.CfDeploy.CloudflareWorkers)
	}
	return signature
}

func assertNarrowBundleCompileShapes(bundles operatorruntime.Bundles) {
	acceptClusterShape(*bundles.Cluster)
	acceptPlatformShape(*bundles.Platform)
	acceptGardenDependencyShape(*bundles.Dependency)
	acceptTrafficShape(*bundles.Traffic)
	acceptWebhookShape(*bundles.Webhook)
	acceptCfDeployShape(*bundles.CfDeploy)
}

func acceptClusterShape(_ struct {
	ProviderAPI operatorruntime.ProviderDoor
}) {
}

func acceptPlatformShape(_ struct {
	InfisicalAdmin operatorruntime.ProviderDoor
	GitHubOrgRead  operatorruntime.ProviderDoor
	FleetRepoWrite operatorruntime.ProviderDoor
}) {
}

func acceptGardenDependencyShape(_ struct {
	VendorEngine    operatorruntime.ProviderDoor
	BrokerToken     operatorruntime.ProviderDoor
	NativeTigrisKey operatorruntime.ProviderDoor
	ReadOnlySeed    operatorruntime.ProviderDoor
}) {
}

func acceptTrafficShape(_ struct {
	Route53       operatorruntime.ProviderDoor
	CloudflareDNS operatorruntime.ProviderDoor
	EdgePublisher operatorruntime.ProviderDoor
}) {
}

func acceptWebhookShape(_ struct {
	MercuryManagement  operatorruntime.ProviderDoor
	LandscapeMercuryKV operatorruntime.ProviderDoor
}) {
}

func acceptCfDeployShape(_ struct {
	CloudflareWorkers operatorruntime.ProviderDoor
}) {
}
