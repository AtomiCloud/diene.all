package main

// DOMAIN WIRING: replaceable Note/KV command composition.
import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/AtomiCloud/diene.go-base/adapters/kv"
	"github.com/AtomiCloud/diene.go-base/lib/note"
)

const Usage = "usage: go-base <slug TEXT|key NAMESPACE KEY|note REDIS_ADDR TITLE BODY>"

func Execute(args []string, stdout io.Writer, stderr io.Writer) int {
	if len(args) == 0 {
		_, _ = fmt.Fprintln(stderr, Usage)
		return 2
	}

	switch args[0] {
	case "slug":
		if len(args) != 2 {
			_, _ = fmt.Fprintln(stderr, Usage)
			return 2
		}
		_, _ = fmt.Fprintln(stdout, note.Slug(args[1]))
		return 0
	case "key":
		if len(args) != 3 {
			_, _ = fmt.Fprintln(stderr, Usage)
			return 2
		}
		_, _ = fmt.Fprintln(stdout, note.NamespacedKey(args[1], args[2]))
		return 0
	case "note":
		if len(args) != 4 {
			_, _ = fmt.Fprintln(stderr, Usage)
			return 2
		}
		store := kv.NewRedisStore(args[1])
		service := note.NewService(store)
		value := note.New(args[2], args[3])
		if err := service.Save(context.Background(), value); err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			_ = store.Close()
			return 1
		}
		loaded, err := service.Load(context.Background(), value.Slug)
		if err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			_ = store.Close()
			return 1
		}
		if err := store.Close(); err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return 1
		}
		_, _ = fmt.Fprintf(stdout, "%s=%s\n", loaded.Slug, loaded.Body)
		return 0
	default:
		_, _ = fmt.Fprintln(stderr, Usage)
		return 2
	}
}

func main() {
	os.Exit(Execute(os.Args[1:], os.Stdout, os.Stderr))
}

// END DOMAIN WIRING
