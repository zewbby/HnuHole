package authprivacy

import (
	"context"
	"errors"
	"strings"
	"testing"

	"golang.org/x/crypto/argon2"
	"golang.org/x/text/unicode/norm"
)

func TestPasswordPolicyAndLegacyVerification(t *testing.T) {
	p, err := NewPasswordPreparer(1, []string{"Password12345"})
	if err != nil {
		t.Fatal(err)
	}
	for _, password := range []string{"", "A1b2C3d4E", "Password12345", "contains spaces 123", "中文abcdefgh123", strings.Repeat("a", 129), strings.Repeat("a", 2049), "\xfflong enough password"} {
		if _, err = p.PreparePassword(context.Background(), password, "private_user"); !errors.Is(err, ErrPasswordPolicy) {
			t.Fatal("invalid new credential accepted")
		}
	}
	for _, password := range []string{"A1b2C3d4E5", "SpecialSymbols123!@#", strings.Repeat("z", 128)} {
		material, er := p.PreparePassword(context.Background(), password, "private_user")
		if er != nil {
			t.Fatal(er)
		}
		if ok, er := p.VerifyPassword(context.Background(), password, material); er != nil || !ok {
			t.Fatal("valid new credential did not verify")
		}
	}
	legacy := "une longue phrase cafe\u0301 secrete!"
	material := PasswordMaterial{Salt: [16]byte{1}, ParametersVersion: 1}
	copy(material.Hash[:], argon2.IDKey([]byte(norm.NFC.String(legacy)), material.Salt[:], 3, 64*1024, 4, 32))
	if ok, er := p.VerifyPassword(context.Background(), legacy, material); er != nil || !ok {
		t.Fatal("legacy credential was locked out")
	}
}

func TestPasswordCapacityAndCancellation(t *testing.T) {
	p, err := NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	p.workers <- struct{}{}
	if _, err := p.PreparePassword(context.Background(), "LongIndependent1234", "someone"); !errors.Is(err, ErrPasswordBusy) {
		t.Fatalf("unbounded queue: %v", err)
	}
	<-p.workers
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := p.PreparePassword(ctx, "LongIndependent1234", "someone"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled work: %v", err)
	}
}
