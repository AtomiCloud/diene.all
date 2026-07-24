// Command manager is the single composition root for the operator template.
package main

import (
	"errors"
	"flag"
	"os"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/AtomiCloud/diene.go-base/internal/operatorruntime"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	config := operatorruntime.DefaultConfig(os.Getenv)
	logOptions := zap.Options{Development: false}
	flags := flag.NewFlagSet("manager", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	operatorruntime.BindFlags(flags, &config)
	logOptions.BindFlags(flags)
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&logOptions)))
	setupLog := ctrl.Log.WithName("setup")
	restConfig, err := ctrl.GetConfig()
	if err != nil {
		setupLog.Error(err, "load Kubernetes configuration")
		return 1
	}
	if err := operatorruntime.Start(ctrl.SetupSignalHandler(), restConfig, config); err != nil {
		setupLog.Error(err, "run manager")
		return 1
	}
	return 0
}
