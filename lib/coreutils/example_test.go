package coreutils_test

import (
	"context"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-core-utils/lib/coreutils"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
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

func ExampleStableHash() {
	first, _ := coreutils.StableHash(map[string]any{"a": 1, "b": 2})
	second, _ := coreutils.StableHash(map[string]any{"b": 2, "a": 1})
	fmt.Println(first == second)
	// Output: true
}

func ExampleMapConcurrent() {
	doubled, _ := coreutils.MapConcurrent(context.Background(), []int{1, 2, 3}, 2,
		func(_ context.Context, value int) (int, error) { return value * 2, nil })
	fmt.Println(doubled)
	// Output: [2 4 6]
}

func ExampleHashFile() {
	filesystem := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	_ = filesystem.WriteText(context.Background(), "/greeting.txt", "hello", interfaces.WriteOptions{CreateParents: true})
	digest, _ := coreutils.HashFile(context.Background(), filesystem, "/greeting.txt")
	fmt.Println(digest)
	// Output: 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
}

func ExampleNowWireInstant() {
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.SetNow(time.Date(2026, 7, 21, 1, 2, 3, 456000000, time.UTC))
	instant, _ := coreutils.NowWireInstant(system)
	fmt.Println(instant)
	// Output: 2026-07-21T01:02:03.456Z
}
