package note

import "strings"

// Note is a stored note identified by its normalized title slug.
type Note struct {
	Slug string
	Body string
}

// Slug normalizes whitespace and casing into a hyphen-separated identifier.
func Slug(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(value)), "-")
}

// NamespacedKey joins a namespace and key for a key-value store.
func NamespacedKey(namespace string, key string) string {
	return namespace + ":" + key
}

// New creates a note from a title and body.
func New(title string, body string) Note {
	return Note{Slug: Slug(title), Body: body}
}
