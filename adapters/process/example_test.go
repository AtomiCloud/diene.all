package process_test

import (
	"context"
	"fmt"

	"github.com/AtomiCloud/diene.go-e2e/adapters/process"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

func ExampleNewTerminal() {
	terminal := process.NewTerminal(process.TerminalOptions{})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"printf", []string{"hello"}, nil, nil, false, false,
	))
	if err != nil {
		panic(err)
	}
	fmt.Println(output.ExitCode, output.Stdout)
	// Output: 0 hello
}

func ExampleTerminal_Run_failingExitCode() {
	// A non-zero exit is OUTPUT, not an error: a harness has to be able to assert
	// on a command that is supposed to fail.
	terminal := process.NewTerminal(process.TerminalOptions{Shell: "/bin/sh"})
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand(
		"exit 3", nil, nil, nil, false, true,
	))
	fmt.Println(output.ExitCode, err)
	// Output: 3 <nil>
}

func ExampleEnviron() {
	for _, entry := range process.Environ(map[string]string{"B": "two", "A": "one"}, []string{"INHERITED=yes"}) {
		fmt.Println(entry)
	}
	// Output:
	// INHERITED=yes
	// A=one
	// B=two
}
