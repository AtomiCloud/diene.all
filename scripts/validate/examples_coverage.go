//go:build ignore

// Command examples_coverage fails when any exported symbol of a target package
// lacks an associated Example function, so full-public-surface example coverage
// is mechanically enforced rather than trusting that whatever examples exist
// compile. Run it with `go run scripts/validate/examples_coverage.go <dir>...`.
package main

import (
	"fmt"
	"go/ast"
	"go/doc"
	"go/parser"
	"go/token"
	"os"
	"sort"
	"strings"
	"unicode"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: examples_coverage <package-dir>...")
		os.Exit(2)
	}
	var missing []string
	for _, dir := range os.Args[1:] {
		expected, covered, err := analyze(dir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "❌ %s: %v\n", dir, err)
			os.Exit(2)
		}
		for _, name := range expected {
			if !isCovered(name, covered) {
				missing = append(missing, dir+": Example"+name)
			}
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		fmt.Fprintln(os.Stderr, "❌ exported symbols without an Example function:")
		for _, entry := range missing {
			fmt.Fprintln(os.Stderr, "  "+entry)
		}
		os.Exit(1)
	}
	fmt.Println("✅ every exported symbol has an Example function")
}

// appendExported appends only the exported candidate names.
func appendExported(names []string, candidates ...string) []string {
	for _, candidate := range candidates {
		if ast.IsExported(candidate) {
			names = append(names, candidate)
		}
	}
	return names
}

// analyze returns the exported symbol names of the package in dir (types,
// functions, methods "Type_Method", and constants/variables) and the set of
// Example function names present in that dir's test files.
func analyze(dir string) ([]string, map[string]bool, error) {
	fileSet := token.NewFileSet()
	packages, err := parser.ParseDir(fileSet, dir, nil, 0)
	if err != nil {
		return nil, nil, err
	}
	covered := map[string]bool{}
	var expected []string
	for name, pkg := range packages {
		if strings.HasSuffix(name, "_test") {
			for _, file := range pkg.Files {
				collectExamples(file, covered)
			}
			continue
		}
		documented := doc.New(pkg, "./"+dir, 0)
		for _, value := range documented.Consts {
			expected = appendExported(expected, value.Names...)
		}
		for _, value := range documented.Vars {
			expected = appendExported(expected, value.Names...)
		}
		for _, function := range documented.Funcs {
			expected = appendExported(expected, function.Name)
		}
		for _, typ := range documented.Types {
			if !ast.IsExported(typ.Name) {
				continue
			}
			expected = append(expected, typ.Name)
			for _, function := range typ.Funcs {
				expected = appendExported(expected, function.Name)
			}
			for _, method := range typ.Methods {
				if ast.IsExported(method.Name) {
					expected = append(expected, typ.Name+"_"+method.Name)
				}
			}
		}
	}
	// A dir may have only a `_test` example package alongside the source package;
	// also scan for examples in the same directory's `<pkg>_test` files already
	// handled above.
	return expected, covered, nil
}

// collectExamples records the name (after the Example prefix) of each Example
// function declared in file.
func collectExamples(file *ast.File, covered map[string]bool) {
	for _, decl := range file.Decls {
		function, ok := decl.(*ast.FuncDecl)
		if !ok || function.Recv != nil {
			continue
		}
		name := function.Name.Name
		if strings.HasPrefix(name, "Example") {
			covered[strings.TrimPrefix(name, "Example")] = true
		}
	}
}

// isCovered reports whether name is satisfied by an example named exactly name,
// or name followed by a lowercase-started suffix (godoc's multiple-example form).
// A trailing uppercase segment denotes a method, so it never satisfies its type.
func isCovered(name string, covered map[string]bool) bool {
	if covered[name] {
		return true
	}
	for candidate := range covered {
		rest, ok := strings.CutPrefix(candidate, name+"_")
		if ok && rest != "" && unicode.IsLower([]rune(rest)[0]) {
			return true
		}
	}
	return false
}
