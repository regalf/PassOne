package store

import "testing"

func TestValidateUsername(t *testing.T) {
	valid := []string{
		"alice",
		"Alice",
		"alice99",
		"alice.bob",
		"alice_bob",
		"alice-bob",
		"alice@example.com",
		"alice+tag",
	}
	for _, u := range valid {
		if err := ValidateUsername(u); err != nil {
			t.Errorf("ValidateUsername(%q) = %v, want nil", u, err)
		}
	}

	invalid := []string{
		"",
		"   ",
		`<img src=x onerror=alert(1)>`,
		`<script>alert(1)</script>`,
		`user"onmouseover="alert(1)`,
		"user'quote",
		"user/name",
		"user\\name",
		"user name",
		"user\nname",
		"user\tname",
		"user;drop",
		"user\x00",
		"é",
	}
	for _, u := range invalid {
		if err := ValidateUsername(u); err == nil {
			t.Errorf("ValidateUsername(%q) = nil, want an error", u)
		}
	}
}

func TestValidateUsernameLength(t *testing.T) {
	long := ""
	for i := 0; i < MaxUsernameLength+1; i++ {
		long += "a"
	}
	if err := ValidateUsername(long); err == nil {
		t.Error("a username longer than the limit was accepted")
	}
	if err := ValidateUsername(long[:MaxUsernameLength]); err != nil {
		t.Errorf("a username of exactly %d characters was rejected: %v", MaxUsernameLength, err)
	}
}

func TestCreatePendingUserRejectsInvalidUsername(t *testing.T) {
	s, err := Open(t.TempDir() + "/test.db")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	if _, err := s.CreatePendingUser(`<img src=x onerror=alert(1)>`); err == nil {
		t.Error("CreatePendingUser accepted a username containing markup")
	}
}
