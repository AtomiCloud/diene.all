// Package examplecov analyzes a Go package's exported API surface and reports
// which units lack an associated Example function, so full example coverage is
// mechanically enforced rather than trusting whatever examples happen to exist.
// It is the cohesive service behind the build-ignored examples_coverage command;
// its operations are exported and externally tested.
//
// The covered API units and the example naming each requires are:
//
//   - package const, var, func, and type T — an ExampleT, or any lowercase-suffix
//     variant ExampleT_xxx (the godoc multiple-example form);
//   - a method or interface method T.M — an exact ExampleT_M;
//   - an exported struct field T.F — an exact ExampleT_f, where f is the field
//     name with a lowercase initial (a Go-valid variant-example suffix that
//     compiles and runs, since Go associates no example with a field directly).
package examplecov

import (
	"fmt"
	"go/ast"
	"go/doc"
	"go/parser"
	"go/token"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode"
)

// Run checks example coverage for each package directory in dirs, writing the
// success line to stdout or the missing-example diagnostics to stderr, and
// returns the process exit code: 0 when every exported unit has an example, 1
// when any is missing, and 2 on a usage or parse fault. It is the whole command
// behavior, so the build-ignored main is one line of wiring.
func Run(dirs []string, stdout, stderr io.Writer) int {
	if len(dirs) == 0 {
		_, _ = fmt.Fprintln(stderr, "usage: examples_coverage <package-dir>...")
		return 2
	}
	var missing []string
	for _, dir := range dirs {
		analysis, err := Analyze(dir)
		if err != nil {
			_, _ = fmt.Fprintf(stderr, "❌ %s: %v\n", dir, err)
			return 2
		}
		for _, requirement := range analysis.Uncovered() {
			missing = append(missing, fmt.Sprintf("%s: %s (want Example%s)", dir, requirement.Symbol, requirement.Name))
		}
	}
	if len(missing) > 0 {
		slices.Sort(missing)
		_, _ = fmt.Fprintln(stderr, "❌ exported symbols without an Example function:")
		for _, entry := range missing {
			_, _ = fmt.Fprintln(stderr, "  "+entry)
		}
		return 1
	}
	_, _ = fmt.Fprintln(stdout, "✅ every exported symbol has an Example function")
	return 0
}

// Requirement is one exported API unit that must have an associated example.
type Requirement struct {
	// Symbol is a human-readable label for diagnostics, e.g. "AppBlock.Landscape field".
	Symbol string
	// Name is the example identifier after the "Example" prefix that satisfies it.
	Name string
	// Exact requires an example named exactly Name (methods, interface methods,
	// and fields); when false a lowercase-suffix variant ExampleName_xxx also
	// satisfies it (types, funcs, consts, vars).
	Exact bool
}

// SatisfiedBy reports whether the present example names cover the requirement.
func (r Requirement) SatisfiedBy(examples map[string]bool) bool {
	if examples[r.Name] {
		return true
	}
	if r.Exact {
		return false
	}
	for name := range examples {
		if rest, ok := strings.CutPrefix(name, r.Name+"_"); ok && rest != "" && unicode.IsLower([]rune(rest)[0]) {
			return true
		}
	}
	return false
}

// Analysis is the exported-symbol requirements and present example names of one
// analyzed package directory.
type Analysis struct {
	// Dir is the analyzed package directory.
	Dir string
	// Requirements is every exported API unit that must have an example.
	Requirements []Requirement
	// Examples is the set of example identifiers (after "Example") in the dir's
	// _test files.
	Examples map[string]bool
}

// Uncovered returns the requirements that no present example satisfies.
func (a Analysis) Uncovered() []Requirement {
	missing := make([]Requirement, 0)
	for _, requirement := range a.Requirements {
		if !requirement.SatisfiedBy(a.Examples) {
			missing = append(missing, requirement)
		}
	}
	return missing
}

// Analyze parses the package in dir with the current-generation stdlib API and
// returns its exported example requirements together with the example names
// present in the dir's _test files. Files named *_test.go supply examples; the
// rest supply the documented API surface.
func Analyze(dir string) (Analysis, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return Analysis{}, err
	}
	fileSet := token.NewFileSet()
	analysis := Analysis{Dir: dir, Examples: map[string]bool{}}
	var sources []*ast.File
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") {
			continue
		}
		file, parseErr := parser.ParseFile(fileSet, filepath.Join(dir, entry.Name()), nil, 0)
		if parseErr != nil {
			return Analysis{}, parseErr
		}
		if strings.HasSuffix(entry.Name(), "_test.go") {
			CollectExamples(file, analysis.Examples)
			continue
		}
		sources = append(sources, file)
	}
	if len(sources) > 0 {
		requirements, reqErr := PackageRequirements(fileSet, sources, dir)
		if reqErr != nil {
			return Analysis{}, reqErr
		}
		analysis.Requirements = requirements
	}
	return analysis, nil
}

// PackageRequirements returns the example requirements of the non-test source
// files of a package: its exported consts, vars, funcs, types, methods,
// interface methods, and struct fields.
func PackageRequirements(fileSet *token.FileSet, sources []*ast.File, dir string) ([]Requirement, error) {
	documented, err := doc.NewFromFiles(fileSet, sources, "example.invalid/"+dir)
	if err != nil {
		return nil, err
	}
	requirements := make([]Requirement, 0)
	for _, value := range documented.Consts {
		requirements = AppendFlexible(requirements, "const", value.Names)
	}
	for _, value := range documented.Vars {
		requirements = AppendFlexible(requirements, "var", value.Names)
	}
	for _, function := range documented.Funcs {
		requirements = AppendFlexible(requirements, "func", []string{function.Name})
	}
	for _, typ := range documented.Types {
		if !ast.IsExported(typ.Name) {
			continue
		}
		requirements = append(requirements, Requirement{Symbol: "type " + typ.Name, Name: typ.Name})
		for _, function := range typ.Funcs {
			requirements = AppendFlexible(requirements, "func", []string{function.Name})
		}
		for _, method := range typ.Methods {
			if ast.IsExported(method.Name) {
				requirements = append(requirements, Requirement{Symbol: typ.Name + "." + method.Name + " method", Name: typ.Name + "_" + method.Name, Exact: true})
			}
		}
		requirements = append(requirements, MemberRequirements(typ)...)
	}
	return requirements, nil
}

// AppendFlexible appends a suffix-flexible requirement for each exported name.
func AppendFlexible(requirements []Requirement, kind string, names []string) []Requirement {
	for _, name := range names {
		if ast.IsExported(name) {
			requirements = append(requirements, Requirement{Symbol: kind + " " + name, Name: name})
		}
	}
	return requirements
}

// MemberRequirements returns exact requirements for a type's interface methods
// and exported struct fields, which go/doc does not surface as methods.
func MemberRequirements(typ *doc.Type) []Requirement {
	requirements := make([]Requirement, 0)
	for _, spec := range typ.Decl.Specs {
		typeSpec, ok := spec.(*ast.TypeSpec)
		if !ok || typeSpec.Name.Name != typ.Name {
			continue
		}
		switch underlying := typeSpec.Type.(type) {
		case *ast.InterfaceType:
			for _, member := range underlying.Methods.List {
				for _, name := range member.Names {
					if ast.IsExported(name.Name) {
						requirements = append(requirements, Requirement{Symbol: typ.Name + "." + name.Name + " method", Name: typ.Name + "_" + name.Name, Exact: true})
					}
				}
			}
		case *ast.StructType:
			for _, member := range underlying.Fields.List {
				for _, name := range member.Names {
					if ast.IsExported(name.Name) {
						requirements = append(requirements, Requirement{Symbol: typ.Name + "." + name.Name + " field", Name: typ.Name + "_" + LowerInitial(name.Name), Exact: true})
					}
				}
			}
		default:
			// Other type kinds (aliases, scalars, funcs) carry no members needing
			// their own example.
		}
	}
	return requirements
}

// LowerInitial lowercases the first rune of name, producing a Go-valid variant
// example suffix for a field (ExampleType_fieldName).
func LowerInitial(name string) string {
	if name == "" {
		return name
	}
	runes := []rune(name)
	runes[0] = unicode.ToLower(runes[0])
	return string(runes)
}

// CollectExamples records the identifier (after the Example prefix) of each
// top-level Example function declared in file.
func CollectExamples(file *ast.File, examples map[string]bool) {
	for _, declaration := range file.Decls {
		function, ok := declaration.(*ast.FuncDecl)
		if !ok || function.Recv != nil {
			continue
		}
		if name, found := strings.CutPrefix(function.Name.Name, "Example"); found {
			examples[name] = true
		}
	}
}
