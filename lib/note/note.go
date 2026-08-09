package note

// DOMAIN WIRING: replaceable Note sample domain.
import "strings"

type Note struct {
	Slug string
	Body string
}

func Slug(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(value)), "-")
}

func NamespacedKey(namespace string, key string) string {
	return namespace + ":" + key
}

func New(title string, body string) Note {
	return Note{Slug: Slug(title), Body: body}
}

// END DOMAIN WIRING
