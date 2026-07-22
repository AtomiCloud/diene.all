package interfaces_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

// ExampleTerminalOutput_Succeeded shows that a non-zero child exit is captured output.
func ExampleTerminalOutput_Succeeded() {
	output := interfaces.TerminalOutput{ExitCode: 2, Stderr: "usage"}
	fmt.Println(output.Succeeded())
	// Output: false
}

// ExampleNewTerminalCommand shows a command constructed with owned inputs.
func ExampleNewTerminalCommand() {
	command := interfaces.NewTerminalCommand("echo", []string{"hello"}, nil, nil, true, false)
	fmt.Println(command.Executable, command.Args[0])
	// Output: echo hello
}
