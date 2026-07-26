// Package publishedapi composes the published API and authentication engines.
package publishedapi

import (
	"errors"

	"github.com/AtomiCloud/diene.go-api-engine/lib/apiengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/authengine"
	"github.com/AtomiCloud/diene.go-auth-engine/lib/logto"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// NewClientTree builds the authenticated outbound API client tree.
func NewClientTree(
	portal problem.ErrorPortal,
	apiConfig apiengine.Config,
	authConfig authengine.Config,
	store authengine.TokenStore,
	system interfaces.System,
	doer apiengine.Doer,
) (*apiengine.ClientTree, error) {
	authProblems, authProblemsErr := authengine.NewProblems(portal)
	resources, resourcesErr := apiConfig.Tree(authProblems)
	provider, providerErr := logto.NewClient(logto.ClientOptions{
		Config:   authConfig,
		HTTP:     doer,
		Problems: authProblems,
		Clock:    system,
	})
	tokens, tokensErr := authengine.NewTokenCache(authengine.TokenCacheOptions{
		Tree:        resources,
		Store:       store,
		Source:      authengine.NewClientCredentialsSource(provider),
		Problems:    authProblems,
		Clock:       system,
		Namespace:   authConfig.Minting.CacheNamespace,
		Skew:        authConfig.Minting.Skew(),
		Concurrency: authConfig.Minting.Concurrency,
	})
	apiProblems, apiProblemsErr := apiengine.NewProblems(portal)
	tree, treeErr := apiengine.NewClientTree(apiengine.TreeOptions{
		Config:   apiConfig,
		Doer:     doer,
		Tokens:   tokens,
		Problems: apiProblems,
	})
	if err := errors.Join(
		authProblemsErr,
		resourcesErr,
		providerErr,
		tokensErr,
		apiProblemsErr,
		treeErr,
	); err != nil {
		return nil, err
	}
	return tree, nil
}
