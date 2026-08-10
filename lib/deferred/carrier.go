package deferred

import (
	"net/url"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

// Carrier field names. They are wire contract, shared with the mobile redeemers,
// so they are declared once here rather than spelled out on both sides of the
// handoff.
const (
	// CarrierTokenField carries the handoff nonce.
	CarrierTokenField = "atomi_handoff"
	// CarrierExpiryField carries the nonce expiry as a canonical RFC 3339 UTC
	// instant.
	CarrierExpiryField = "atomi_handoff_expires"
	// CarrierMountField carries the mount path the app should redeem against, so
	// a consumer that moved the handoff endpoint does not need a second release
	// of the app to match.
	CarrierMountField = "atomi_handoff_mount"
)

// ClipboardMarker prefixes the iOS clipboard payload. Without a marker the app
// cannot tell a handoff payload from whatever the user happened to copy last.
const ClipboardMarker = "atomi-handoff:"

// AndroidReferrer builds the Android Install Referrer payload for a handoff.
//
// The Install Referrer is a query string the Play Store hands to an app on first
// launch, so the payload is URL-encoded and deliberately small: the referrer has
// a length ceiling, and it is visible to anything that can read the install
// referral, which is exactly why it carries a one-time nonce rather than a token.
func AndroidReferrer(handoff Handoff, mount string) (string, error) {
	expiry, err := carrierExpiry(handoff.ExpiresAt)
	if err != nil {
		return "", err
	}
	values := url.Values{}
	values.Set(CarrierTokenField, handoff.Token)
	values.Set(CarrierExpiryField, expiry)
	values.Set(CarrierMountField, carrierMount(mount))
	return values.Encode(), nil
}

// ParseAndroidReferrer reads a handoff back out of an Install Referrer payload,
// returning the nonce and the mount to redeem against.
//
// It is the mobile side of [AndroidReferrer], shipped here so both halves of the
// wire contract change together.
func ParseAndroidReferrer(referrer string) (Handoff, string, error) {
	values, err := url.ParseQuery(referrer)
	if err != nil {
		return Handoff{}, "", err
	}
	token := values.Get(CarrierTokenField)
	if token == "" {
		return Handoff{}, "", &CarrierError{Field: CarrierTokenField}
	}
	expiry, err := coreutils.ParseRFC3339UTC(values.Get(CarrierExpiryField))
	if err != nil {
		return Handoff{}, "", err
	}
	return Handoff{Token: token, ExpiresAt: expiry}, carrierMount(values.Get(CarrierMountField)), nil
}

// ClipboardPayload builds the iOS clipboard payload for a handoff.
//
// iOS has no install-referrer equivalent, so the web client writes a marked
// payload to the general pasteboard and the app reads it on first launch. The
// marker prefix is what keeps the app from treating arbitrary copied text as a
// login. The body reuses the referrer encoding on purpose: one codec for both
// carriers means one wire contract to keep in step with the mobile redeemers.
func ClipboardPayload(handoff Handoff, mount string) (string, error) {
	encoded, err := AndroidReferrer(handoff, mount)
	if err != nil {
		return "", err
	}
	return ClipboardMarker + encoded, nil
}

// ParseClipboardPayload reads a handoff back out of a clipboard payload,
// rejecting any text that does not carry the marker.
func ParseClipboardPayload(payload string) (Handoff, string, error) {
	body, marked := strings.CutPrefix(payload, ClipboardMarker)
	if !marked {
		return Handoff{}, "", &CarrierError{Field: ClipboardMarker}
	}
	return ParseAndroidReferrer(body)
}

// CarrierError reports a store carrier that is missing a required field.
//
// It is a plain typed error rather than a Problem: carrier parsing happens on the
// CLIENT, before any service context or error portal exists, so there is no portal
// to attribute the failure to.
type CarrierError struct {
	// Field is the missing or unrecognised carrier field.
	Field string
}

// Error implements the error interface.
func (e *CarrierError) Error() string {
	return "deferred login carrier is missing " + e.Field
}

// carrierExpiry renders the nonce expiry in the family's canonical wire form, so
// a mobile redeemer parses one instant format across every language family.
func carrierExpiry(expiry time.Time) (string, error) {
	return coreutils.FormatRFC3339UTC(expiry)
}

// carrierMount falls back to the documented default mount, so an older carrier
// that predates the mount field still redeems.
func carrierMount(mount string) string {
	if mount == "" {
		return authengine.DefaultHandoffPath
	}
	return mount
}
