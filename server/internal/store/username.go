package store

import (
	"errors"
	"fmt"
	"strings"
)

// ErrInvalidUsername is returned when a username does not satisfy the
// naming rules (see ValidateUsername).
var ErrInvalidUsername = errors.New("invalid username")

// MaxUsernameLength is the maximum number of characters of a username.
const MaxUsernameLength = 64

// ValidateUsername checks that a username is safe to store and to display.
//
// The username ends up in the admin web UI, in logs and in API responses, so
// it is restricted to a conservative character set: ASCII letters, digits and
// a few punctuation marks that carry no meaning for a renderer. This keeps
// markup (and therefore script injection) out of the database in the first
// place, instead of relying on the UI to escape it.
//
// Non-ASCII letters are rejected on purpose: they allow homoglyph tricks
// ("аdmin" with a Cyrillic 'а') and need Unicode normalization to compare
// safely.
func ValidateUsername(username string) error {
	name := strings.TrimSpace(username)
	if name == "" {
		return fmt.Errorf("%w: empty", ErrInvalidUsername)
	}
	if len([]rune(name)) > MaxUsernameLength {
		return fmt.Errorf("%w: longer than %d characters", ErrInvalidUsername, MaxUsernameLength)
	}
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z':
		case r >= 'A' && r <= 'Z':
		case r >= '0' && r <= '9':
		case r == '-' || r == '_' || r == '.' || r == '@' || r == '+':
		default:
			return fmt.Errorf("%w: contains an unsupported character", ErrInvalidUsername)
		}
	}
	return nil
}
