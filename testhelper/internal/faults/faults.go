// Package faults centralizes the canonical problem minting and error
// normalization shared by the testhelper mocks. Intrinsic mock faults resolve
// their RFC 9457 type URI through the single-source builder
// [problem.TypeURI] (never string concatenation), and every non-nil error a
// mock surfaces is normalized so it carries a [problem.Error] while remaining
// errors.Is/errors.As-compatible with its original cause.
package faults

import (
	"errors"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// Version is the fixed problem type-URI version segment for testhelper faults.
const Version = "v1"

// Portal is the fixed, valid LPSM portal the testhelper faults mint their type
// URIs from. It is a constant identity for the in-memory doubles, so the type
// URIs are stable and never hand-authored per row.
func Portal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.diene.atomicloud.com",
		Landscape: "diene",
		Platform:  "go",
		Service:   "interfaces",
		Module:    "testhelper",
	}
}

// PathNotFound mints the canonical path-not-found (404) fault for path.
func PathNotFound(path string) error {
	return NewIntrinsic("path-not-found", "Path not found", path, 404)
}

// DirectoryNotEmpty mints the canonical directory-not-empty (409) fault for path.
func DirectoryNotEmpty(path string) error {
	return NewIntrinsic("directory-not-empty", "Directory not empty", path, 409)
}

// TerminalNotScripted mints the canonical terminal-result-not-scripted (500)
// fault naming the executable whose result was missing.
func TerminalNotScripted(executable string) error {
	return NewIntrinsic("terminal-result-not-scripted", "Terminal result not scripted", executable, 500)
}

// Normalize guarantees a non-nil error carries a [problem.Error]. An error
// already carrying one anywhere in its chain is returned unchanged; any other
// error is wrapped so errors.As recovers a [problem.Error] while errors.Is
// still reaches the original cause. A nil error stays nil.
func Normalize(err error) error {
	if err == nil {
		return nil
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) && problemErr != nil {
		return err
	}
	return problem.WrapError(problem.FromObject(err, problem.DefaultTransformOptions()), err)
}

// NewIntrinsic builds a problem-typed error whose type URI comes from the fixed
// portal. The portal and version are compile-time constants known to be valid,
// so the builder never errors here.
func NewIntrinsic(id, title, detail string, status int) error {
	typeURI, _ := problem.TypeURI(Portal(), Version, id)
	occurrence := detail
	return problem.NewError(problem.Problem{
		Type:   typeURI,
		Title:  title,
		Status: status,
		Detail: &occurrence,
		Data:   map[string]any{"id": id},
	})
}
