package store

import "errors"

// Errori di dominio del database.
var (
	ErrNotFound = errors.New("risorsa non trovata")
	ErrConflict = errors.New("conflitto di revisione")
)
