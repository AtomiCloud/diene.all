// Command archcheck enforces the positive thin-controller boundary. Each real
// controller must delegate to an explicitly approved pure decision package and
// must contain no inline business decision. The Phase-2 foundation window may
// contain only the package sentinel and no reconcilers.
//
// Inline decisions are detected structurally: arithmetic and magnitude
// comparison operators belong in the pure decision layer. Equality guards and
// boolean logic remain valid controller glue.
package main

import (
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const controllersDir = "adapters/operator/controllers"

var forbidden = map[token.Token]string{
	token.MUL: "*", token.QUO: "/", token.REM: "%",
	token.LSS: "<", token.GTR: ">", token.LEQ: "<=", token.GEQ: ">=",
}

var approvedDecisionImports = map[string]struct{}{
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/lifecycle": {},
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "❌ operator architecture: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("✅ operator thin-controller boundary passed")
}

func run() error {
	entries, err := os.ReadDir(controllersDir)
	if err != nil {
		return fmt.Errorf("read %s: %w", controllersDir, err)
	}

	fset := token.NewFileSet()
	checked := 0
	reconcilers := 0
	var violations []string

	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}

		path := filepath.Join(controllersDir, name)
		fmt.Printf("🔎 checked controller path: %s\n", path)
		checked++
		file, parseErr := parser.ParseFile(fset, path, nil, 0)
		if parseErr != nil {
			return fmt.Errorf("parse %s: %w", path, parseErr)
		}

		if name != "conditions.go" {
			reconcilers++
			approved := false
			for _, spec := range file.Imports {
				importPath, unquoteErr := strconv.Unquote(spec.Path.Value)
				if unquoteErr != nil {
					violations = append(violations, fmt.Sprintf("%s: unreadable import %s", path, spec.Path.Value))
					continue
				}
				if _, ok := approvedDecisionImports[importPath]; ok {
					approved = true
					continue
				}
				if strings.Contains(importPath, "/lib/operator/") {
					violations = append(violations, fmt.Sprintf("%s: unapproved decision import %s", path, importPath))
				}
			}
			if !approved {
				violations = append(violations, path+": imports no approved pure decision package")
			}
		}

		ast.Inspect(file, func(n ast.Node) bool {
			binary, ok := n.(*ast.BinaryExpr)
			if !ok {
				return true
			}
			if op, forbiddenHere := forbidden[binary.Op]; forbiddenHere {
				violations = append(violations,
					fmt.Sprintf("%s: inline decision operator %q", fset.Position(binary.Pos()), op))
			}
			return true
		})
	}

	if checked == 0 {
		return errors.New("no non-test controller package files found")
	}
	fmt.Printf("🧮 checked controller files: %d; reconciler files: %d\n", checked, reconcilers)
	if reconcilers == 0 {
		if checked != 1 {
			violations = append(violations, "zero reconcilers require exactly one package sentinel")
		} else {
			fmt.Println("PASS: no reconcilers in the Phase-2 foundation window")
		}
	}
	if len(violations) > 0 {
		return fmt.Errorf("thin-controller boundary violated:\n  %s", strings.Join(violations, "\n  "))
	}
	return nil
}
