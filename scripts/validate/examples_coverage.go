// Command examples_coverage fails when any exported symbol of a target package
// lacks an associated Example function, so full-public-surface example coverage
// is mechanically enforced rather than trusting that whatever examples exist
// compile. All behavior lives in the externally tested internal/examplecov
// service; this file is only command wiring. Run it with
// `go run ./scripts/validate <dir>...` (or naming this file).
package main

import (
	"os"

	"github.com/AtomiCloud/diene.go-config/internal/examplecov"
)

func main() { os.Exit(examplecov.Run(os.Args[1:], os.Stdout, os.Stderr)) }
