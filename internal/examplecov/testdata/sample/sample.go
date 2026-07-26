// Package sample is a fixture exercising every exported API unit kind the
// analyzer classifies. It is parsed as source by examplecov, never compiled.
package sample

// Answer is a const.
const Answer = 42

// Global is a var.
var Global = "g"

// Meters is a scalar type with neither fields nor methods.
type Meters int

// Widget is a struct with an exported and an unexported field.
type Widget struct {
	// Name is exported and needs a field example.
	Name   string
	hidden int
}

// Render is a method that needs an exact method example.
func (Widget) Render() string { return "" }

// Reader is an interface whose method needs an exact method example.
type Reader interface {
	Read() string
}

// Build constructs a Widget, so go/doc lists it under the type.
func Build() Widget { return Widget{} }
