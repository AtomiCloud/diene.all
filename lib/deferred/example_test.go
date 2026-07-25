package deferred_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/deferred"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

func ExampleMinter_Mint() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	minter, _ := deferred.NewMinter(deferred.MinterOptions{
		Store:    testhelper.NewMemoryDeferredStore(),
		Provider: testhelper.NewFakeProvider(testhelper.FakeProviderOptions{}),
		Problems: idp.Problems(),
		Clock:    idp.Clock(),
	})

	ctx := context.Background()
	handoff, _ := minter.Mint(ctx, authengine.Session{Subject: "user-1"}, nil)

	// The provider one-time token is minted at REDEEM time, so the nonce can sit in
	// a store carrier for the whole install.
	token, err := minter.Exchange(ctx, handoff.Token)
	fmt.Println(token.Value, err == nil)

	// Redeeming twice is a replay, not a retry.
	_, err = minter.Exchange(ctx, handoff.Token)
	fmt.Println(err != nil)
	// Output:
	// one-time-user-1 true
	// true
}

func ExampleAndroidReferrer() {
	handoff := deferred.Handoff{
		Token:     "nonce-value",
		ExpiresAt: testhelper.FixedNow().Add(authengine.DeferredTokenLifetime),
	}

	referrer, _ := deferred.AndroidReferrer(handoff, "")
	parsed, mount, _ := deferred.ParseAndroidReferrer(referrer)

	fmt.Println(parsed.Token, mount)
	// Output: nonce-value /app-handoff
}

func ExampleClipboardPayload() {
	handoff := deferred.Handoff{
		Token:     "nonce-value",
		ExpiresAt: testhelper.FixedNow().Add(authengine.DeferredTokenLifetime),
	}

	payload, _ := deferred.ClipboardPayload(handoff, "/handoff")
	parsed, mount, _ := deferred.ParseClipboardPayload(payload)

	fmt.Println(parsed.Token, mount)

	// Unmarked clipboard text is never treated as a login.
	_, _, err := deferred.ParseClipboardPayload("something the user copied")
	fmt.Println(err != nil)
	// Output:
	// nonce-value /handoff
	// true
}
