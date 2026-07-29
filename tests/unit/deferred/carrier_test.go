package deferred_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/deferred"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

// sampleHandoff is a minted handoff with a canonical expiry.
func sampleHandoff() deferred.Handoff {
	return deferred.Handoff{
		Token:     "nonce-value",
		ExpiresAt: testhelper.FixedNow().Add(authengine.DeferredTokenLifetime),
	}
}

func TestAndroidReferrerRoundTrips(t *testing.T) {
	t.Parallel()

	handoff := sampleHandoff()

	referrer, err := deferred.AndroidReferrer(handoff, "/handoff")
	requireNoError(t, err)

	parsed, mount, err := deferred.ParseAndroidReferrer(referrer)
	requireNoError(t, err)

	if parsed.Token != handoff.Token {
		t.Fatalf("expected the nonce to survive the carrier, got %q", parsed.Token)
	}
	if !parsed.ExpiresAt.Equal(handoff.ExpiresAt) {
		t.Fatalf("expected the expiry to survive, got %s", parsed.ExpiresAt)
	}
	if mount != "/handoff" {
		t.Fatalf("expected the configured mount to survive, got %q", mount)
	}
}

func TestClipboardPayloadRoundTripsAndIsMarked(t *testing.T) {
	t.Parallel()

	handoff := sampleHandoff()

	payload, err := deferred.ClipboardPayload(handoff, "")
	requireNoError(t, err)

	if len(payload) <= len(deferred.ClipboardMarker) ||
		payload[:len(deferred.ClipboardMarker)] != deferred.ClipboardMarker {
		t.Fatalf("expected a marked payload, got %q", payload)
	}

	parsed, mount, err := deferred.ParseClipboardPayload(payload)
	requireNoError(t, err)
	if parsed.Token != handoff.Token {
		t.Fatalf("expected the nonce to survive the clipboard, got %q", parsed.Token)
	}
	// A carrier that omits the mount redeems against the documented default.
	if mount != authengine.DefaultHandoffPath {
		t.Fatalf("expected the default mount, got %q", mount)
	}
}

func TestParseClipboardPayloadRefusesUnmarkedText(t *testing.T) {
	t.Parallel()

	// The pasteboard carries whatever the user last copied; without the marker an
	// app would treat arbitrary text as a login.
	_, _, err := deferred.ParseClipboardPayload("just something the user copied")

	var carrier *deferred.CarrierError
	if !asCarrierError(err, &carrier) {
		t.Fatalf("expected a carrier error, got %v", err)
	}
	if carrier.Field != deferred.ClipboardMarker {
		t.Fatalf("expected the marker to be named, got %q", carrier.Field)
	}
	if carrier.Error() == "" {
		t.Fatal("expected the carrier error to render a message")
	}
}

func TestParseCarrierRejectsAMissingNonce(t *testing.T) {
	t.Parallel()

	_, _, err := deferred.ParseAndroidReferrer("atomi_handoff_expires=2026-07-25T12%3A15%3A00.000Z")

	var carrier *deferred.CarrierError
	if !asCarrierError(err, &carrier) {
		t.Fatalf("expected a carrier error, got %v", err)
	}
	if carrier.Field != deferred.CarrierTokenField {
		t.Fatalf("expected the token field to be named, got %q", carrier.Field)
	}
}

func TestParseCarrierRejectsUnparseableInput(t *testing.T) {
	t.Parallel()

	if _, _, err := deferred.ParseAndroidReferrer("%zz"); err == nil {
		t.Fatal("expected an unparseable referrer to be rejected")
	}
	if _, _, err := deferred.ParseAndroidReferrer("atomi_handoff=n&atomi_handoff_expires=yesterday"); err == nil {
		t.Fatal("expected a non-canonical expiry to be rejected")
	}
	if _, _, err := deferred.ParseClipboardPayload(deferred.ClipboardMarker + "%zz"); err == nil {
		t.Fatal("expected an unparseable clipboard body to be rejected")
	}
}

func TestCarrierRejectsAnUnrenderableExpiry(t *testing.T) {
	t.Parallel()

	// Beyond the four-digit calendar the canonical wire form cannot represent the
	// instant, and a carrier with an unreadable expiry is worse than none.
	beyond := deferred.Handoff{Token: "n", ExpiresAt: time.Date(12000, time.January, 1, 0, 0, 0, 0, time.UTC)}

	if _, err := deferred.AndroidReferrer(beyond, ""); err == nil {
		t.Fatal("expected an unrenderable expiry to be rejected")
	}
	if _, err := deferred.ClipboardPayload(beyond, ""); err == nil {
		t.Fatal("expected an unrenderable expiry to be rejected on the clipboard path too")
	}
}

// asCarrierError reports whether err is a carrier error and binds it to target.
func asCarrierError(err error, target **deferred.CarrierError) bool {
	carrier, ok := err.(*deferred.CarrierError) //nolint:errorlint // the carrier error is never wrapped
	if ok {
		*target = carrier
	}
	return ok
}
