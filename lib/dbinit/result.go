package dbinit

// Result is the successful one-shot db-init report.
type Result struct {
	Seeded int `json:"seeded"`
}
