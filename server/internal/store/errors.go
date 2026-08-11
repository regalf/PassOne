package store

import "errors"

// Database domain errors.
var (
	ErrNotFound = errors.New("resource not found")
	ErrConflict = errors.New("revision conflict")
)
