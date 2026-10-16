package authprivacy

import (
	"bufio"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"math/big"
	"net"
	"net/textproto"
	"strings"
	"testing"
	"time"
)

type capturedSMTPMessage struct{ recipient, body string }

func localSMTPFixture(t *testing.T, mode string) (string, <-chan capturedSMTPMessage) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal("local SMTP fixture unavailable")
	}
	messages := make(chan capturedSMTPMessage, 1)
	done := make(chan struct{})
	t.Cleanup(func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			t.Error("SMTP fixture failed to stop")
		}
	})
	go func() {
		defer close(done)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
		reader := bufio.NewReader(conn)
		fmt.Fprint(conn, "220 local-authlab SMTP\r\n")
		recipient := ""
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				return
			}
			line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
			upper := strings.ToUpper(line)
			switch {
			case strings.HasPrefix(upper, "EHLO "):
				fmt.Fprint(conn, "250-local-authlab\r\n250 8BITMIME\r\n")
			case strings.HasPrefix(upper, "HELO "):
				fmt.Fprint(conn, "250 local-authlab\r\n")
			case strings.HasPrefix(upper, "MAIL FROM:"):
				fmt.Fprint(conn, "250 sender ok\r\n")
			case strings.HasPrefix(upper, "RCPT TO:"):
				recipient = line
				fmt.Fprint(conn, "250 recipient ok\r\n")
			case upper == "DATA":
				if mode == "reject_before_data" {
					fmt.Fprint(conn, "554 payload not accepted\r\n")
					continue
				}
				fmt.Fprint(conn, "354 send message\r\n")
				body, err := textproto.NewReader(reader).ReadDotBytes()
				if err != nil {
					return
				}
				messages <- capturedSMTPMessage{recipient: recipient, body: string(body)}
				if mode == "disconnect_after_data" {
					return
				}
				if mode == "reject_after_data" {
					fmt.Fprint(conn, "550 payload rejected\r\n")
					return
				}
				if mode == "defer_after_data" {
					fmt.Fprint(conn, "450 payload temporarily rejected\r\n")
					return
				}
				if mode == "malformed_after_data" {
					fmt.Fprint(conn, "not an SMTP response\r\n")
					return
				}
				fmt.Fprint(conn, "250 accepted\r\n")
			case upper == "QUIT":
				if mode != "disconnect_on_quit" {
					fmt.Fprint(conn, "221 bye\r\n")
				}
				return
			default:
				fmt.Fprint(conn, "500 unsupported fixture command\r\n")
			}
		}
	}()
	return listener.Addr().String(), messages
}

func TestSMTPActualWireAcceptanceAndAmbiguity(t *testing.T) {
	for _, spec := range []struct {
		mode     string
		outcome  MailOutcome
		captured bool
	}{{"accept", MailSent, true}, {"disconnect_after_data", MailUnknown, true}, {"reject_before_data", MailNotSent, false}, {"disconnect_on_quit", MailSent, true}, {"reject_after_data", MailNotSent, true}, {"defer_after_data", MailNotSent, true}, {"malformed_after_data", MailUnknown, true}} {
		t.Run(spec.mode, func(t *testing.T) {
			address, messages := localSMTPFixture(t, spec.mode)
			provider, err := NewSMTPProvider(SMTPConfig{Address: address, From: "otp@verifier.test", Timeout: time.Second, AllowInsecureLoopback: true})
			if err != nil {
				t.Fatal(err)
			}
			outcome, _ := provider.SendOTP(context.Background(), [32]byte{1}, "wirefixture@hainanu.edu.cn", "001234")
			if outcome != spec.outcome {
				t.Fatal("unexpected SMTP delivery classification")
			}
			if spec.captured {
				select {
				case message := <-messages:
					if !strings.Contains(message.body, "001234") || !strings.Contains(message.recipient, "wirefixture@hainanu.edu.cn") || !strings.Contains(message.body, "Message-ID:") {
						t.Fatal("SMTP wire payload malformed")
					}
				case <-time.After(time.Second):
					t.Fatal("SMTP message absent")
				}
			}
		})
	}
}

func TestSMTPCertificatePolicyHasNoRemotePlaintextFallback(t *testing.T) {
	if _, err := NewSMTPProvider(SMTPConfig{Address: "mail.invalid:25", From: "otp@verifier.test", Timeout: time.Second, AllowInsecureLoopback: true}); err == nil {
		t.Fatal("remote plaintext SMTP accepted")
	}
	if _, err := NewSMTPProvider(SMTPConfig{Address: "mail.invalid:25", From: "otp@verifier.test", Timeout: time.Second, TLSConfig: &tls.Config{InsecureSkipVerify: true}}); err == nil {
		t.Fatal("unverified SMTP TLS accepted")
	}
	address, messages := localSMTPFixture(t, "accept")
	provider, err := NewSMTPProvider(SMTPConfig{Address: address, From: "otp@verifier.test", Timeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if outcome, err := provider.SendOTP(context.Background(), [32]byte{1}, "wirefixture@hainanu.edu.cn", "001234"); err == nil || outcome != MailNotSent {
		t.Fatal("missing STARTTLS fallback accepted")
	}
	select {
	case <-messages:
		t.Fatal("plaintext SMTP message was sent despite TLS policy")
	default:
	}
}

func TestSMTPTLSConfigIsIsolatedFromCallerMutation(t *testing.T) {
	caller := &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: x509.NewCertPool(), ClientCAs: x509.NewCertPool()}
	provider, err := NewSMTPProvider(SMTPConfig{Address: "127.0.0.1:1", From: "otp@verifier.test", Timeout: time.Second, TLSConfig: caller})
	if err != nil {
		t.Fatal(err)
	}
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal("certificate fixture key unavailable")
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	der, err := x509.CreateCertificate(rand.Reader, template, template, publicKey, privateKey)
	if err != nil {
		t.Fatal("certificate fixture unavailable")
	}
	certificate, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal("certificate fixture malformed")
	}
	caller.InsecureSkipVerify = true
	caller.MinVersion = tls.VersionTLS10
	caller.RootCAs.AddCert(certificate)
	caller.ClientCAs.AddCert(certificate)
	stored := provider.config.TLSConfig
	if stored == caller || stored.InsecureSkipVerify || stored.MinVersion != tls.VersionTLS12 || stored.RootCAs == caller.RootCAs || stored.ClientCAs == caller.ClientCAs || stored.RootCAs.Equal(caller.RootCAs) || stored.ClientCAs.Equal(caller.ClientCAs) {
		t.Fatal("caller mutation changed the stored SMTP TLS policy")
	}
	// Even internal corruption must fail before any network or SMTP payload.
	stored.InsecureSkipVerify = true
	outcome, err := provider.SendOTP(context.Background(), [32]byte{1}, "wirefixture@hainanu.edu.cn", "001234")
	if outcome != MailNotSent || err == nil || !strings.Contains(err.Error(), "cannot be disabled") {
		t.Fatal("runtime disabled verification was not rejected before dialing")
	}
}
