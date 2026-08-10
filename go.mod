// Minimal module so GoReleaser's Go builder can compile the goreleaser.go placeholder.
// The shipped binary is the prebuilt Bun binary swapped in by the post-build hook.
module releaser

go 1.22
