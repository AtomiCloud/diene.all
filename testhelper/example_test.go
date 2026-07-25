package testhelper_test

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
)

func ExampleInMemoryTraceEmitter() {
	emitter := testhelper.NewInMemoryTraceEmitter()
	if err := emitter.Emit(testhelper.SampleTraceRecord()); err != nil {
		panic(err)
	}
	fmt.Println(len(emitter.Records()), emitter.Records()[0].Status)

	// Output:
	// 1 ok
}

func ExampleAssertTraceRecords() {
	emitter := testhelper.NewInMemoryTraceEmitter()
	want := []otel.TraceRecord{testhelper.SampleTraceRecord()}
	if err := emitter.Emit(want[0]); err != nil {
		panic(err)
	}
	testhelper.AssertTraceRecords(exampleTestingT{}, emitter, want)
	fmt.Println("trace assertion passed")

	// Output:
	// trace assertion passed
}

type exampleTestingT struct{}

func (exampleTestingT) Helper() {}

func (exampleTestingT) Fatalf(format string, args ...any) { panic(fmt.Sprintf(format, args...)) }
