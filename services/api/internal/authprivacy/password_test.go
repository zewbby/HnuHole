package authprivacy

import (
	"context"
	"errors"
	"strings"
	"testing"

	"golang.org/x/crypto/argon2"
	"golang.org/x/text/unicode/norm"
)

func TestPasswordPolicyAndNormalization(t *testing.T) {
	p, err := NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	for _, password := range []string{"short", "passwordpassword123!", "private_user123456789", strings.Repeat("a", 129), strings.Repeat("a", 2049), "\xfflong enough password"} {
		if _, err := p.PreparePassword(context.Background(), password, "private_user"); !errors.Is(err, ErrPasswordPolicy) {
			t.Fatalf("policy accepted invalid input: %v", err)
		}
	}
	password := "une longue phrase cafe\u0301 secrete"
	material, err := p.PreparePassword(context.Background(), password, "private_user")
	if err != nil {
		t.Fatal(err)
	}
	want := argon2.IDKey([]byte(norm.NFC.String(password)), material.Salt[:], 3, 64*1024, 4, 32)
	if string(want) != string(material.Hash[:]) || material.ParametersVersion != 1 {
		t.Fatal("password material did not use the stored NFC/profile contract")
	}
}

func TestPasswordCapacityAndCancellation(t *testing.T) {
	p, err := NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	p.workers <- struct{}{}
	if _, err := p.PreparePassword(context.Background(), "a long independent password", "someone"); !errors.Is(err, ErrPasswordBusy) {
		t.Fatalf("unbounded queue: %v", err)
	}
	<-p.workers
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := p.PreparePassword(ctx, "a long independent password", "someone"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled work: %v", err)
	}
}
