package onboard_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/onboard"
	"github.com/AtomiCloud/diene.go-auth-engine/testhelper"
)

func ExampleSync_Run() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	problems := idp.Problems()
	tree, _ := authengine.NewResourceTree(
		problems,
		authengine.Resource{Name: "alcohol-zinc", Indicator: "https://api.zinc.invalid"},
		authengine.Resource{Name: "nitroso-tin", Indicator: "https://api.tin.invalid"},
	)
	provider := testhelper.NewFakeProvider(testhelper.FakeProviderOptions{})
	cache, _ := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:     tree,
		Store:    testhelper.NewMemoryTokenStore(),
		Source:   authengine.NewClientCredentialsSource(provider),
		Problems: problems,
		Clock:    idp.Clock(),
	})

	registered := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject: "user-1",
		"alcohol_zinc":          "true",
		"nitroso_tin":           "true",
	})
	round, _ := onboard.NewSync(onboard.SyncOptions{
		Backends: []onboard.Backend{
			testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "alcohol-zinc"}),
			testhelper.NewFakeBackend(testhelper.FakeBackendOptions{Name: "nitroso-tin", NeedsConfiguration: true}),
		},
		Claims:    provider,
		Refresher: testhelper.NewFakeRefresher(registered),
		Tokens:    cache,
		Problems:  problems,
	})

	// State is keyed PER BACKEND: ready on one while the other still needs its
	// app-specific onboarding step is a normal state.
	states, _ := round.Run(context.Background(), registered)
	fmt.Println(states["alcohol-zinc"].Phase, states["nitroso-tin"].Phase)
	// Output: ready needs-onboarding
}

func ExampleSelector_Home() {
	idp, _ := testhelper.NewFakeIDP(testhelper.FakeIDPOptions{})
	pinger := testhelper.NewFakePinger()
	pinger.SetLatency("lapras", 40)
	pinger.SetLatency("mew", 9)
	selector, _ := onboard.NewSelector(onboard.SelectorOptions{
		Pinger: pinger, Problems: idp.Problems(),
	})

	document := []onboard.Landscape{
		{Name: "lapras", Display: "Singapore", Healthy: true},
		{Name: "mew", Display: "Frankfurt", Healthy: true},
	}
	ctx := context.Background()

	// A new caller pings and picks; a returning caller routes straight home from
	// its claim, with no extra step.
	newUser := authengine.NewClaimMapper().Map(authengine.Claims{authengine.ClaimSubject: "user-1"})
	picked, _ := selector.Home(ctx, newUser, document)

	returning := authengine.NewClaimMapper().Map(authengine.Claims{
		authengine.ClaimSubject:       "user-1",
		authengine.ClaimHomeLandscape: "lapras",
	})
	home, _ := selector.Home(ctx, returning, document)

	fmt.Println(picked.Name, home.Name)
	// Output: mew lapras
}
