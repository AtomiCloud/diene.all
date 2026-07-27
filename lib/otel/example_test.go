package otel_test

import (
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-otel/lib/otel"
)

func ExampleDefaultConfig() {
	config := otel.DefaultConfig()
	fmt.Println(config.Logs.Enabled, config.Logs.Exporter.Otlp.Enabled)
	fmt.Println(config.Metrics.Interval, config.Traces.Sampler.Type)

	// Output:
	// true false
	// PT60S parentbased_traceidratio
}

func ExampleConfig_Validate() {
	config := otel.DefaultConfig()
	fmt.Println(config.Validate() == nil)

	config.Logs.Exporter.Otlp.Enabled = true
	fmt.Println(config.Validate() != nil)

	// Output:
	// true
	// true
}

func ExampleResourceAttributes() {
	attributes, err := otel.ResourceAttributes(otel.AppIdentity{
		Landscape: "lapras",
		Platform:  "payments",
		Service:   "checkout",
		Module:    "api",
		Version:   "1.2.3",
	})
	if err != nil {
		panic(err)
	}
	fmt.Println(attributes[otel.AttrDeploymentEnvironmentName])
	fmt.Println(attributes[otel.AttrServiceNamespace], attributes[otel.AttrServiceName])
	fmt.Println(attributes[otel.AttrAtomiModule])

	// Output:
	// lapras
	// payments checkout
	// api
}

func ExampleJSONSchema() {
	schema := otel.JSONSchema()
	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		panic("schema properties must be an object")
	}
	fmt.Println(otel.SchemaKey(), schema["additionalProperties"])
	fmt.Println(len(properties))

	// Output:
	// otel false
	// 3
}

func ExampleParseFixedDuration() {
	duration, err := otel.ParseFixedDuration("PT10S")
	if err != nil {
		panic(err)
	}
	fmt.Println(duration)

	// Output:
	// 10s
}

func ExampleNewTraceRecord() {
	record := otel.NewTraceRecord(
		time.Date(2026, 7, 25, 12, 0, 0, 0, time.UTC),
		"checkout",
		map[string]any{"cart.items": 3},
		[]otel.TraceEvent{otel.NewTraceEvent("validated", nil)},
		otel.TraceStatusOK,
		nil,
	)
	fmt.Println(record.Name, record.Status, len(record.Events))

	// Output:
	// checkout ok 1
}

func ExampleOtlpSignalURL() {
	url, err := otel.OtlpSignalURL("https://collector.example:4318", otel.SignalTraces)
	if err != nil {
		panic(err)
	}
	fmt.Println(url)

	// Output:
	// https://collector.example:4318/v1/traces
}
