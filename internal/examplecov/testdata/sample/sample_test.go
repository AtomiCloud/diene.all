package sample_test

// widget and the helpers below exercise CollectExamples' skips: a method (has a
// receiver) and a non-Example function are ignored.
type widget struct{}

func (widget) Method() {}

func helper() {}

func ExampleAnswer()        {}
func ExampleMeters()        {}
func ExampleWidget_usage()  {} // covers type Widget via a lowercase-suffix variant
func ExampleWidget_Render() {} // covers the Render method exactly
func ExampleWidget_name()   {} // covers the Name field exactly
func ExampleReader()        {}
func ExampleBuild()         {}

// Intentionally missing: Global (a var, flexible) and Reader_Read (an interface
// method, exact), so Uncovered exercises both unsatisfied branches.
