package operatorruntime

import (
	"errors"
	"fmt"
	"reflect"
	"strings"
)

// Stable capability-construction error categories. Concrete errors unwrap to
// these values so startup callers can fail closed with errors.Is while retaining
// the controller and credential names through errors.As.
var (
	ErrCredentialRequired          = errors.New("controller credential required")
	ErrCredentialOutsideEnabledSet = errors.New("credential outside enabled controller set")
	ErrDoorAbsent                  = errors.New("capability door absent")
	ErrControllerBundleRequired    = errors.New("controller capability bundle required")
	ErrProblemNotFolded            = errors.New("problem sub-component not yet folded")
)

const (
	controllerCluster    = "cluster"
	controllerPlatform   = "platform"
	controllerDependency = "dependency"
	controllerTraffic    = "traffic"
	controllerWebhook    = "webhook"
	controllerCfDeploy   = "cf-deploy"
)

const (
	capClusterProviderAPI       = "provider-api"
	capPlatformInfisicalAdmin   = "infisical-admin"
	capPlatformGitHubOrgRead    = "github-org-read"
	capPlatformFleetRepoWrite   = "fleet-repo-write"
	capDependencyVendorEngine   = "vendor-engine"
	capDependencyBrokerToken    = "broker-token"
	capDependencyNativeTigris   = "native-tigris-key"
	capDependencyReadOnlySeed   = "read-only-seed"
	capTrafficRoute53           = "route53"
	capTrafficCloudflareDNS     = "cloudflare-dns"
	capTrafficEdgePublisher     = "edge-publisher"
	capWebhookMercuryManagement = "mercury-management"
	capWebhookLandscapeKV       = "landscape-mercury-kv"
	capCfDeployWorkers          = "cloudflare-workers"
	capInfisicalWrite           = "infisical-write"
	capT4RootPath               = "t4-root-path"
)

// MissingCredentialError identifies one required credential omitted from an
// enabled controller's group.
type MissingCredentialError struct {
	Controller string
	Credential string
}

// Error implements error.
func (e *MissingCredentialError) Error() string {
	return fmt.Sprintf("%s: %s controller is missing %s", ErrCredentialRequired, e.Controller, e.Credential)
}

// Unwrap exposes ErrCredentialRequired.
func (*MissingCredentialError) Unwrap() error { return ErrCredentialRequired }

// CredentialOutsideEnabledSetError identifies credential material which has no
// enabled controller authorized to receive it.
type CredentialOutsideEnabledSetError struct {
	Controller string
	Credential string
}

// Error implements error.
func (e *CredentialOutsideEnabledSetError) Error() string {
	return fmt.Sprintf("%s: %s credential is not allowed by %s scope", ErrCredentialOutsideEnabledSet, e.Credential, e.Controller)
}

// Unwrap exposes ErrCredentialOutsideEnabledSet.
func (*CredentialOutsideEnabledSetError) Unwrap() error {
	return ErrCredentialOutsideEnabledSet
}

// MissingBundleError identifies an enabled registration seam which was not
// given its controller-scoped bundle.
type MissingBundleError struct {
	Controller string
}

// Error implements error.
func (e *MissingBundleError) Error() string {
	return fmt.Sprintf("%s: %s controller is enabled without its bundle", ErrControllerBundleRequired, e.Controller)
}

// Unwrap exposes ErrControllerBundleRequired.
func (*MissingBundleError) Unwrap() error { return ErrControllerBundleRequired }

// MalformedBundleError identifies a controller bundle whose door does not
// satisfy the registration contract. ActualKind is retained as an exported
// field for source compatibility but is deliberately left empty by registration
// validation: an injected door's Kind() is untrusted provider input, so it is
// never retained and cannot leak through the error string or errors.As metadata.
// Provider availability errors are likewise not retained.
type MalformedBundleError struct {
	Controller string
	Door       string
	Reason     string
	ActualKind string
}

// Error implements error.
func (e *MalformedBundleError) Error() string {
	if e.ActualKind != "" {
		return fmt.Sprintf(
			"%s: %s controller %s door %s (got kind %q)",
			ErrControllerBundleRequired,
			e.Controller,
			e.Door,
			e.Reason,
			e.ActualKind,
		)
	}
	return fmt.Sprintf(
		"%s: %s controller %s door %s",
		ErrControllerBundleRequired,
		e.Controller,
		e.Door,
		e.Reason,
	)
}

// Unwrap exposes ErrControllerBundleRequired.
func (*MalformedBundleError) Unwrap() error { return ErrControllerBundleRequired }

// ProviderDoor is the deliberately small Phase 2 provider port. Phase 3
// composition replaces present markers with narrow adapter interfaces; callers
// can already require optional doors without risking a nil dereference.
type ProviderDoor interface {
	Kind() string
	Available() error
}

func validateRequiredDoor(controller, expectedKind string, door ProviderDoor) error {
	if err := validateDoorKind(controller, expectedKind, door); err != nil {
		return err
	}
	if err := door.Available(); err != nil {
		return &MalformedBundleError{
			Controller: controller,
			Door:       expectedKind,
			Reason:     "is unavailable",
		}
	}
	return nil
}

func validateOptionalDoor(controller, expectedKind string, door ProviderDoor) error {
	if err := validateDoorKind(controller, expectedKind, door); err != nil {
		return err
	}
	if _, absent := door.(*AbsentDoor); absent {
		return nil
	}
	if err := door.Available(); err != nil {
		return &MalformedBundleError{
			Controller: controller,
			Door:       expectedKind,
			Reason:     "is unavailable without typed absence",
		}
	}
	return nil
}

func validateDoorKind(controller, expectedKind string, door ProviderDoor) error {
	if door == nil {
		return &MalformedBundleError{
			Controller: controller,
			Door:       expectedKind,
			Reason:     "is nil",
		}
	}
	if providerDoorIsTypedNil(door) {
		return &MalformedBundleError{
			Controller: controller,
			Door:       expectedKind,
			Reason:     "contains a typed nil",
		}
	}
	if door.Kind() != expectedKind {
		return &MalformedBundleError{
			Controller: controller,
			Door:       expectedKind,
			Reason:     "has the wrong kind",
		}
	}
	return nil
}

// providerDoorIsTypedNil keeps ProviderDoor open to narrow adapter
// implementations while covering the nil-able dynamic kinds an interface may
// hold before invoking their methods. All other validation uses the port
// directly.
func providerDoorIsTypedNil(door ProviderDoor) bool {
	value := reflect.ValueOf(door)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}

// AbsentDoor is an explicit, typed optional capability refusal. It is both a
// non-nil ProviderDoor and an errors.Is/errors.As-able error returned by
// Available, so derive-only dependency profiles fail at reconcile time instead
// of dereferencing a missing client.
type AbsentDoor struct {
	kind string
}

// Kind names the unavailable capability.
func (d *AbsentDoor) Kind() string { return d.kind }

// Available returns the typed refusal.
func (d *AbsentDoor) Available() error { return d }

// Error implements error.
func (d *AbsentDoor) Error() string { return fmt.Sprintf("%s: %s", ErrDoorAbsent, d.kind) }

// Unwrap exposes ErrDoorAbsent.
func (*AbsentDoor) Unwrap() error { return ErrDoorAbsent }

type presentDoor struct {
	kind string
}

func (d *presentDoor) Kind() string   { return d.kind }
func (*presentDoor) Available() error { return nil }

// ClusterCredentials is the cluster controller's complete credential group.
type ClusterCredentials struct {
	ProviderAPI string
}

// PlatformCredentials is the platform controller's complete credential group.
type PlatformCredentials struct {
	InfisicalAdmin string
	GitHubOrgRead  string
	FleetRepoWrite string
}

// DependencyCredentials is the dependency controller's optional-door inventory.
// Every field is optional because Garden derive-only operation is valid.
type DependencyCredentials struct {
	VendorEngine    string
	BrokerToken     string
	NativeTigrisKey string
	ReadOnlySeed    bool
}

// TrafficCredentials is the traffic controller's complete credential group.
type TrafficCredentials struct {
	Route53       string
	CloudflareDNS string
	EdgePublisher string
}

// WebhookCredentials is the webhook controller's complete credential group.
type WebhookCredentials struct {
	MercuryManagement  string
	LandscapeMercuryKV string
}

// CfDeployCredentials is the cf-deploy controller's complete credential group.
type CfDeployCredentials struct {
	CloudflareWorkers string
}

// CredentialSet is the explicit presence-only inventory presented to the
// composition root. Values are opaque references in Phase 2 and are never
// parsed or retained in a bundle. InfisicalWrite and T4RootPath are represented
// solely so an accidentally mounted broad Primordial credential fails closed;
// neither is admitted to any controller bundle.
type CredentialSet struct {
	Cluster        ClusterCredentials
	Platform       PlatformCredentials
	Dependency     DependencyCredentials
	Traffic        TrafficCredentials
	Webhook        WebhookCredentials
	CfDeploy       CfDeployCredentials
	InfisicalWrite string
	T4RootPath     string
}

// ClusterBundle exposes only the cluster provider API door.
type ClusterBundle struct {
	ProviderAPI ProviderDoor
}

// PlatformBundle exposes only the three platform-owned provider doors.
type PlatformBundle struct {
	InfisicalAdmin ProviderDoor
	GitHubOrgRead  ProviderDoor
	FleetRepoWrite ProviderDoor
}

// DependencyBundle is the Garden-safe dependency shape. Its four doors are
// optional and explicit; structurally, there is no Infisical-write or T4-root
// door on this type.
type DependencyBundle struct {
	VendorEngine    ProviderDoor
	BrokerToken     ProviderDoor
	NativeTigrisKey ProviderDoor
	ReadOnlySeed    ProviderDoor
}

// TrafficBundle exposes only traffic-owned DNS and publisher doors.
type TrafficBundle struct {
	Route53       ProviderDoor
	CloudflareDNS ProviderDoor
	EdgePublisher ProviderDoor
}

// WebhookBundle exposes only webhook-owned mercury doors.
type WebhookBundle struct {
	MercuryManagement  ProviderDoor
	LandscapeMercuryKV ProviderDoor
}

// CfDeployBundle exposes only the Cloudflare Workers versions door.
type CfDeployBundle struct {
	CloudflareWorkers ProviderDoor
}

// Bundles is the construction result. A nil bundle means its controller was not
// enabled; an enabled dependency bundle may contain typed AbsentDoor values.
type Bundles struct {
	Cluster    *ClusterBundle
	Platform   *PlatformBundle
	Dependency *DependencyBundle
	Traffic    *TrafficBundle
	Webhook    *WebhookBundle
	CfDeploy   *CfDeployBundle
}

// BuildBundles deterministically validates the enable-by-credential matrix and
// constructs controller-scoped capability bundles without performing I/O.
func BuildBundles(config Config, credentials CredentialSet) (Bundles, error) {
	if config.EnableProblem {
		return Bundles{}, ErrProblemNotFolded
	}
	if supplied(credentials.InfisicalWrite) {
		return Bundles{}, &CredentialOutsideEnabledSetError{
			Controller: controllerDependency,
			Credential: capInfisicalWrite,
		}
	}
	if supplied(credentials.T4RootPath) {
		return Bundles{}, &CredentialOutsideEnabledSetError{
			Controller: "primordial",
			Credential: capT4RootPath,
		}
	}

	groups := []credentialGroup{
		{
			controller: controllerCluster,
			enabled:    config.EnableCluster,
			required:   true,
			credentials: []credentialPresence{
				{name: capClusterProviderAPI, supplied: supplied(credentials.Cluster.ProviderAPI)},
			},
		},
		{
			controller: controllerPlatform,
			enabled:    config.EnablePlatform,
			required:   true,
			credentials: []credentialPresence{
				{name: capPlatformInfisicalAdmin, supplied: supplied(credentials.Platform.InfisicalAdmin)},
				{name: capPlatformGitHubOrgRead, supplied: supplied(credentials.Platform.GitHubOrgRead)},
				{name: capPlatformFleetRepoWrite, supplied: supplied(credentials.Platform.FleetRepoWrite)},
			},
		},
		{
			controller: controllerDependency,
			enabled:    config.EnableDependency,
			credentials: []credentialPresence{
				{name: capDependencyVendorEngine, supplied: supplied(credentials.Dependency.VendorEngine)},
				{name: capDependencyBrokerToken, supplied: supplied(credentials.Dependency.BrokerToken)},
				{name: capDependencyNativeTigris, supplied: supplied(credentials.Dependency.NativeTigrisKey)},
				{name: capDependencyReadOnlySeed, supplied: credentials.Dependency.ReadOnlySeed},
			},
		},
		{
			controller: controllerTraffic,
			enabled:    config.EnableTraffic,
			required:   true,
			credentials: []credentialPresence{
				{name: capTrafficRoute53, supplied: supplied(credentials.Traffic.Route53)},
				{name: capTrafficCloudflareDNS, supplied: supplied(credentials.Traffic.CloudflareDNS)},
				{name: capTrafficEdgePublisher, supplied: supplied(credentials.Traffic.EdgePublisher)},
			},
		},
		{
			controller: controllerWebhook,
			enabled:    config.EnableWebhook,
			required:   true,
			credentials: []credentialPresence{
				{name: capWebhookMercuryManagement, supplied: supplied(credentials.Webhook.MercuryManagement)},
				{name: capWebhookLandscapeKV, supplied: supplied(credentials.Webhook.LandscapeMercuryKV)},
			},
		},
		{
			controller: controllerCfDeploy,
			enabled:    config.EnableCfDeploy,
			required:   true,
			credentials: []credentialPresence{
				{name: capCfDeployWorkers, supplied: supplied(credentials.CfDeploy.CloudflareWorkers)},
			},
		},
	}
	for _, group := range groups {
		if err := group.validate(); err != nil {
			return Bundles{}, err
		}
	}

	return constructBundles(config, credentials), nil
}

type credentialPresence struct {
	name     string
	supplied bool
}

type credentialGroup struct {
	controller  string
	enabled     bool
	required    bool
	credentials []credentialPresence
}

func (g credentialGroup) validate() error {
	for _, credential := range g.credentials {
		if g.enabled && g.required && !credential.supplied {
			return &MissingCredentialError{Controller: g.controller, Credential: credential.name}
		}
		if !g.enabled && credential.supplied {
			return &CredentialOutsideEnabledSetError{Controller: g.controller, Credential: credential.name}
		}
	}
	return nil
}

func constructBundles(config Config, credentials CredentialSet) Bundles {
	var bundles Bundles
	if config.EnableCluster {
		bundles.Cluster = &ClusterBundle{ProviderAPI: newDoor(capClusterProviderAPI, credentials.Cluster.ProviderAPI)}
	}
	if config.EnablePlatform {
		bundles.Platform = &PlatformBundle{
			InfisicalAdmin: newDoor(capPlatformInfisicalAdmin, credentials.Platform.InfisicalAdmin),
			GitHubOrgRead:  newDoor(capPlatformGitHubOrgRead, credentials.Platform.GitHubOrgRead),
			FleetRepoWrite: newDoor(capPlatformFleetRepoWrite, credentials.Platform.FleetRepoWrite),
		}
	}
	if config.EnableDependency {
		readOnlySeedMarker := ""
		if credentials.Dependency.ReadOnlySeed {
			readOnlySeedMarker = "present"
		}
		bundles.Dependency = &DependencyBundle{
			VendorEngine:    newDoor(capDependencyVendorEngine, credentials.Dependency.VendorEngine),
			BrokerToken:     newDoor(capDependencyBrokerToken, credentials.Dependency.BrokerToken),
			NativeTigrisKey: newDoor(capDependencyNativeTigris, credentials.Dependency.NativeTigrisKey),
			ReadOnlySeed:    newDoor(capDependencyReadOnlySeed, readOnlySeedMarker),
		}
	}
	if config.EnableTraffic {
		bundles.Traffic = &TrafficBundle{
			Route53:       newDoor(capTrafficRoute53, credentials.Traffic.Route53),
			CloudflareDNS: newDoor(capTrafficCloudflareDNS, credentials.Traffic.CloudflareDNS),
			EdgePublisher: newDoor(capTrafficEdgePublisher, credentials.Traffic.EdgePublisher),
		}
	}
	if config.EnableWebhook {
		bundles.Webhook = &WebhookBundle{
			MercuryManagement:  newDoor(capWebhookMercuryManagement, credentials.Webhook.MercuryManagement),
			LandscapeMercuryKV: newDoor(capWebhookLandscapeKV, credentials.Webhook.LandscapeMercuryKV),
		}
	}
	if config.EnableCfDeploy {
		bundles.CfDeploy = &CfDeployBundle{CloudflareWorkers: newDoor(capCfDeployWorkers, credentials.CfDeploy.CloudflareWorkers)}
	}
	return bundles
}

func newDoor(kind, reference string) ProviderDoor {
	if !supplied(reference) {
		return &AbsentDoor{kind: kind}
	}
	return &presentDoor{kind: kind}
}

func supplied(value string) bool {
	return strings.TrimSpace(value) != ""
}
