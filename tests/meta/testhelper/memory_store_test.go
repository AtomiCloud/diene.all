package testhelper_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-lib/lib/note"
	"github.com/AtomiCloud/diene.go-lib/testhelper"
)

func TestMemoryStoreContract(t *testing.T) {
	t.Parallel()

	store := testhelper.NewMemoryStore()
	service := note.NewService(store)
	want := note.New("Meta Contract", "consumer fake")

	if err := service.Save(context.Background(), want); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	got, err := service.Load(context.Background(), want.Slug)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got != want {
		t.Fatalf("Load() = %#v, want %#v", got, want)
	}
}

func TestMemoryStoreFailures(t *testing.T) {
	t.Parallel()

	want := errors.New("injected failure")
	store := testhelper.NewMemoryStore()
	store.SaveError = want
	if err := store.Save(context.Background(), "key", "value"); !errors.Is(err, want) {
		t.Fatalf("Save() error = %v, want %v", err, want)
	}
	store.LoadError = want
	if _, err := store.Load(context.Background(), "key"); !errors.Is(err, want) {
		t.Fatalf("Load() error = %v, want %v", err, want)
	}
}
