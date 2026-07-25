// Package testhelper provides the fakes and assertions a consumer of
// github.com/AtomiCloud/diene.go-api-engine would otherwise rebuild in every
// test suite.
//
// Two kinds of pain motivate it. Testing a multi-backend client tree means
// standing up several backends that each answer differently, which is a fixture
// nobody wants to hand-roll twice: [FakeBackend] and [NewFakeTree] do it in a
// line. And testing the 3-case classification means producing RFC 9457
// envelopes with the right `data` extension: [ProblemResponse] and
// [Canned] mint them, so a test can assert how a problem travels without first
// becoming an expert on the envelope's wire shape.
//
// The assertions ([AssertOutcome], [AssertProblem], [CheckProblem]) exist for
// the same reason: every consumer would otherwise write the same errors.As
// dance followed by field-by-field comparison.
//
// This package is for tests. It is a normal (non-test) package so consumers can
// import it, but nothing in the engine depends on it.
package testhelper
