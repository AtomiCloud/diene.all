package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	consumerapp "github.com/AtomiCloud/diene.go-consumer/cmd/go-consumer/app"
)

func main() {
	os.Exit(run())
}

func run() int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	workingDirectory, err := os.Getwd()
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, "resolve working directory:", err)
		return consumerapp.ExitRuntime
	}
	application := consumerapp.New(consumerapp.Options{
		Name: filepathBase(os.Args[0]),
		PID:  os.Getpid(),
	})
	code, executeErr := application.Execute(ctx, consumerapp.Invocation{
		Args:             os.Args[1:],
		Env:              processEnvironment(),
		WorkingDirectory: workingDirectory,
	}, os.Stdout, os.Stderr)
	if executeErr != nil {
		_, _ = fmt.Fprintln(os.Stderr, executeErr)
		return consumerapp.ExitRuntime
	}
	return code
}

func filepathBase(value string) string {
	value = strings.TrimRight(value, string(os.PathSeparator))
	if index := strings.LastIndexByte(value, os.PathSeparator); index >= 0 {
		return value[index+1:]
	}
	return value
}

func processEnvironment() map[string]string {
	environment := make(map[string]string)
	for _, entry := range os.Environ() {
		key, value, _ := strings.Cut(entry, "=")
		environment[key] = value
	}
	return environment
}
