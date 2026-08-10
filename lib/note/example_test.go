package note_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-lib/lib/note"
)

func ExampleNew() {
	value := note.New("Living Documentation", "examples compile as consumer code")
	fmt.Println(value.Slug)
	// Output: living-documentation
}

func ExampleNamespacedKey() {
	fmt.Println(note.NamespacedKey("notes", "living-documentation"))
	// Output: notes:living-documentation
}
