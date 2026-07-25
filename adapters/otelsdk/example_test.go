package otelsdk_test

import (
	"context"
	"fmt"

	interfaceshelper "github.com/AtomiCloud/diene.go-interfaces/testhelper"
	"github.com/AtomiCloud/diene.go-otel/adapters/otelsdk"
	"github.com/AtomiCloud/diene.go-otel/lib/otel"
	"github.com/AtomiCloud/diene.go-otel/testhelper"
)

func ExampleNew() {
	runtime, err := otelsdk.New(
		context.Background(),
		otel.DefaultConfig(),
		testhelper.SampleIdentity(),
		otelsdk.WithSystem(interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})),
	)
	if err != nil {
		panic(err)
	}
	defer func() {
		if shutdownErr := runtime.Shutdown(context.Background()); shutdownErr != nil {
			panic(shutdownErr)
		}
	}()
	fmt.Println(runtime.Active())

	// Output:
	// {false false false}
}

func ExampleRuntime_TraceEmitter() {
	traces := testhelper.NewInMemoryTraceEmitter()
	runtime, err := otelsdk.New(
		context.Background(),
		otel.DefaultConfig(),
		testhelper.SampleIdentity(),
		otelsdk.WithSystem(interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})),
		otelsdk.WithTraceEmitter(traces),
	)
	if err != nil {
		panic(err)
	}
	if err := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil {
		panic(err)
	}
	fmt.Println(len(traces.Records()), traces.Records()[0].Name)

	// Output:
	// 1 sample-span
}

func ExampleNew_withInjectedSeams() {
	logs := testhelper.NewInMemoryLoggerSink()
	metrics := testhelper.NewInMemoryMetricsCollector()
	traces := testhelper.NewInMemoryTraceEmitter()
	runtime, err := otelsdk.New(
		context.Background(),
		otel.DefaultConfig(),
		testhelper.SampleIdentity(),
		otelsdk.WithSystem(interfaceshelper.NewInMemorySystem(interfaceshelper.InMemorySystemOptions{})),
		otelsdk.WithLoggerSink(logs),
		otelsdk.WithMetricsCollector(metrics),
		otelsdk.WithTraceEmitter(traces),
	)
	if err != nil {
		panic(err)
	}
	if err := runtime.LoggerSink().Emit(testhelper.SampleLogRecord()); err != nil {
		panic(err)
	}
	if err := runtime.MetricsCollector().Emit(testhelper.SampleMetricRecord()); err != nil {
		panic(err)
	}
	if err := runtime.TraceEmitter().Emit(testhelper.SampleTraceRecord()); err != nil {
		panic(err)
	}
	fmt.Println(len(logs.Records()), len(metrics.Records()), len(traces.Records()))

	// Output:
	// 1 1 1
}
