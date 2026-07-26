package testhelper_test

import "encoding/json"

// jsonRoundTrip renders a typed block through the shipped struct tags and back
// into the JSON-like map the config validator takes.
//
// Going through encoding/json rather than hand-building the map is the point:
// it is what proves the Go field names and the published schema key names agree.
func jsonRoundTrip(blockKey string, block any) (map[string]any, error) {
	encoded, err := json.Marshal(map[string]any{blockKey: block})
	if err != nil {
		return nil, err
	}
	var instance map[string]any
	if err := json.Unmarshal(encoded, &instance); err != nil {
		return nil, err
	}
	return instance, nil
}
