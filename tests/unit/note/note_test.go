package note_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-lib/lib/note"
	"github.com/AtomiCloud/diene.go-lib/testhelper"
)

func TestSlugAndNamespacedKey(t *testing.T) {
	t.Parallel()

	if got := note.Slug("Hello   World"); got != "hello-world" {
		t.Fatalf("Slug() = %q, want %q", got, "hello-world")
	}
	if got := note.NamespacedKey("notes", "hello-world"); got != "notes:hello-world" {
		t.Fatalf("NamespacedKey() = %q, want %q", got, "notes:hello-world")
	}
}

func TestServiceJourney(t *testing.T) {
	t.Parallel()

	store := testhelper.NewMemoryStore()
	service := note.NewService(store)
	value := note.New("Hello World", "from the domain")

	if err := service.Save(context.Background(), value); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	loaded, err := service.Load(context.Background(), value.Slug)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if loaded != value {
		t.Fatalf("Load() = %#v, want %#v", loaded, value)
	}
}

func TestServiceErrors(t *testing.T) {
	t.Parallel()

	want := errors.New("store unavailable")
	store := testhelper.NewMemoryStore()
	store.SaveError = want
	store.LoadError = want
	service := note.NewService(store)

	if err := service.Save(context.Background(), note.New("Failure", "body")); !errors.Is(err, want) {
		t.Fatalf("Save() error = %v, want %v", err, want)
	}
	if _, err := service.Load(context.Background(), "failure"); !errors.Is(err, want) {
		t.Fatalf("Load() error = %v, want %v", err, want)
	}
}
