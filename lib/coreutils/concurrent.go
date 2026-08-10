package coreutils

import (
	"context"
	"sync"
)

// MapConcurrent applies transform to every item using at most concurrency
// workers while preserving input order in the result. It returns the first
// error reported by any invocation and cancels the derived context handed to
// pending work; a concurrency below one is raised to one. When the parent
// context is cancelled before the work completes the cancellation error is
// returned and no partial result is exposed.
func MapConcurrent[Input any, Output any](
	ctx context.Context,
	items []Input,
	concurrency int,
	transform func(context.Context, Input) (Output, error),
) ([]Output, error) {
	if concurrency < 1 {
		concurrency = 1
	}
	results := make([]Output, len(items))
	if len(items) == 0 {
		return results, nil
	}
	derived, cancel := context.WithCancel(ctx)
	defer cancel()
	semaphore := make(chan struct{}, concurrency)
	var waitGroup sync.WaitGroup
	var once sync.Once
	var firstError error
schedule:
	for index := range items {
		select {
		case <-derived.Done():
			break schedule
		case semaphore <- struct{}{}:
			waitGroup.Add(1)
			go func(position int) {
				defer waitGroup.Done()
				defer func() { <-semaphore }()
				output, errorValue := transform(derived, items[position])
				if errorValue != nil {
					once.Do(func() {
						firstError = errorValue
						cancel()
					})
					return
				}
				results[position] = output
			}(index)
		}
	}
	waitGroup.Wait()
	if firstError != nil {
		return nil, firstError
	}
	if errorValue := derived.Err(); errorValue != nil {
		return nil, errorValue
	}
	return results, nil
}
