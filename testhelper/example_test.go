package testhelper_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

// ExampleCheckError shows the consumer pattern: a fallible API returns
// (T, error); the helper recovers and matches the carried Problem in one call.
func ExampleCheckError() {
	load := func() (string, error) {
		envelope := problem.Problem{
			Type:   "https://docs/v1/entity-not-found",
			Title:  "Entity not found",
			Status: 404,
		}
		return "", problem.NewError(envelope)
	}

	_, err := load()
	envelope, checkErr := testhelper.CheckError(err,
		testhelper.ExpectID("entity-not-found"),
		testhelper.ExpectStatus(404),
	)
	fmt.Println(checkErr, envelope.Title)
	// Output: <nil> Entity not found
}

// ExampleSampleProblem shows the builder minting a valid fixture whose type URI
// comes from the single-source builder.
func ExampleSampleProblem() {
	fmt.Println(testhelper.SampleProblem().Type)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found
}
