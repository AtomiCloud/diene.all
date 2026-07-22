package coreutils_test

import (
	"context"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
)

func ExampleNamespacedKey() {
	key, _ := coreutils.NamespacedKey("Mobile App", "Current User")
	fmt.Println(key)
	// Output: mobile-app:current-user
}

func ExampleEnvironmentToNestedMap() {
	config, _ := coreutils.EnvironmentToNestedMap(map[string]string{"ATOMI_AUTH__SCOPES__0": "openid"}, "ATOMI_")
	fmt.Println(config["auth"])
	// Output: map[scopes:[openid]]
}

func ExampleWireCodec() {
	value, _ := coreutils.NewWireDate(2026, 7, 21)
	fmt.Println(coreutils.WireCodec{}.EncodeDate(value))
	// Output: 2026-07-21
}

func ExampleSleep() {
	_ = coreutils.Sleep(context.Background(), time.Duration(0))
	fmt.Println("complete")
	// Output: complete
}
