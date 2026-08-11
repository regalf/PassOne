package store

import "errors"

// Database domain errors.
var (
	ErrNotFound = errors.New("risorsa non trovata")
	ErrConflict = errors.New("conflitto di revisione")
)
