//go:build ignore

package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/AtomiCloud/diene.go-consumer/lib/appconfig"
)

func main() {
	output := flag.String("out", "schemas/go-consumer.schema.json", "schema output path")
	flag.Parse()

	schema, err := appconfig.Schema()
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose schema: %v\n", err)
		os.Exit(1)
	}
	raw, err := schema.Marshal()
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal schema: %v\n", err)
		os.Exit(1)
	}
	if err = os.MkdirAll(filepath.Dir(*output), 0o750); err != nil {
		fmt.Fprintf(os.Stderr, "create schema directory: %v\n", err)
		os.Exit(1)
	}
	raw = append(raw, '\n')
	if err = os.WriteFile(*output, raw, 0o600); err != nil {
		fmt.Fprintf(os.Stderr, "write schema: %v\n", err)
		os.Exit(1)
	}
}
