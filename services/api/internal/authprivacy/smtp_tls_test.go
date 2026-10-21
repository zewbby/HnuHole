package authprivacy

import (
	"bufio"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"math/big"
	"net"
	"strings"
	"testing"
	"time"
)

func implicitSMTPFixture(t *testing.T, mode string) (string, *x509.CertPool, <-chan capturedSMTPMessage) {
	t.Helper()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cert := &x509.Certificate{SerialNumber: big.NewInt(7), NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, DNSNames: []string{"smtp.fixture.test"}, IsCA: true, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, public, private)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(parsed)
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: private}}})
	if err != nil {
		t.Fatal(err)
	}
	messages := make(chan capturedSMTPMessage, 1)
	done := make(chan struct{})
	t.Cleanup(func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			t.Error("TLS SMTP fixture did not stop")
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
		if _, err = fmt.Fprint(conn, "220 fixture ESMTP\r\n"); err != nil {
			return
		}
		reader := bufio.NewReader(conn)
		recipient := ""
		authenticated := false
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				return
			}
			line = strings.TrimSpace(line)
			switch {
			case strings.HasPrefix(line, "EHLO "):
				fmt.Fprint(conn, "250-fixture\r\n250 AUTH PLAIN\r\n")
			case strings.HasPrefix(line, "AUTH PLAIN "):
				raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(line, "AUTH PLAIN "))
				if mode == "reject-auth" || err != nil || string(raw) != "\x00fixture@qq.com\x00abcdefghijklmnop" {
					fmt.Fprint(conn, "535 rejected\r\n")
					continue
				}
				authenticated = true
				fmt.Fprint(conn, "235 authenticated\r\n")
			case strings.HasPrefix(line, "MAIL FROM:"):
				if !authenticated {
					fmt.Fprint(conn, "530 authenticate first\r\n")
					continue
				}
				fmt.Fprint(conn, "250 ok\r\n")
			case strings.HasPrefix(line, "RCPT TO:"):
				recipient = line
				fmt.Fprint(conn, "250 ok\r\n")
			case line == "DATA":
				if !authenticated {
					fmt.Fprint(conn, "530 authenticate first\r\n")
					continue
				}
				fmt.Fprint(conn, "354 continue\r\n")
				var body strings.Builder
				for {
					data, err := reader.ReadString('\n')
					if err != nil {
						return
					}
					if data == ".\r\n" {
						break
					}
					body.WriteString(data)
				}
				messages <- capturedSMTPMessage{recipient: recipient, body: body.String()}
				if mode == "drop" {
					return
				}
				fmt.Fprint(conn, "250 accepted\r\n")
			case line == "QUIT":
				fmt.Fprint(conn, "221 bye\r\n")
				return
			default:
				fmt.Fprint(conn, "500 unsupported\r\n")
			}
		}
	}()
	return listener.Addr().String(), roots, messages
}

func TestSMTPImplicitTLSAuthenticatedDeliveryAndUnknownOutcome(t *testing.T) {
	for _, mode := range []string{"accept", "drop", "reject-auth", "untrusted", "wrong-host"} {
		t.Run(mode, func(t *testing.T) {
			address, roots, messages := implicitSMTPFixture(t, mode)
			config := SMTPConfig{Address: address, From: "fixture@qq.com", Username: "fixture@qq.com", Password: "abcdefghijklmnop", Timeout: time.Second, ImplicitTLS: true, TLSConfig: &tls.Config{RootCAs: roots}}
			if mode == "untrusted" {
				config.TLSConfig.RootCAs = x509.NewCertPool()
			}
			if mode == "wrong-host" {
				config.ServerName = "wrong.fixture.test"
			}
			provider, err := NewSMTPProvider(config)
			if err != nil {
				t.Fatal("fixture provider rejected")
			}
			outcome, err := provider.SendOTP(context.Background(), [32]byte{9}, "fixture@hainanu.edu.cn", "001234")
			switch mode {
			case "accept":
				if outcome != MailSent || err != nil {
					t.Fatal("authenticated TLS delivery failed")
				}
			case "drop":
				if outcome != MailUnknown || err == nil {
					t.Fatal("lost DATA acceptance was not unknown")
				}
			default:
				if outcome != MailNotSent || err == nil {
					t.Fatal("authentication/certificate failure was accepted")
				}
			}
			if mode == "accept" || mode == "drop" {
				select {
				case message := <-messages:
					if !strings.Contains(message.recipient, "fixture@hainanu.edu.cn") || !strings.Contains(message.body, "001234") {
						t.Fatal("SMTP payload did not reach fixture")
					}
				default:
					t.Fatal("SMTP fixture did not capture payload")
				}
			} else {
				select {
				case <-messages:
					t.Fatal("payload sent after TLS/auth failure")
				default:
				}
			}
		})
	}
}

func TestSMTPRejectsAmbiguousTransportAndAuthentication(t *testing.T) {
	cases := []SMTPConfig{
		{ImplicitTLS: true, AllowInsecureLoopback: true},
		{Username: "fixture@qq.com"},
		{Username: "fixture\x00bad", Password: "secret"},
		{Username: "fixture", Password: "secret\nsecond"},
	}
	for _, candidate := range cases {
		candidate.Address = "127.0.0.1:465"
		candidate.From = "fixture@qq.com"
		candidate.Timeout = time.Second
		if _, err := NewSMTPProvider(candidate); err == nil {
			t.Fatal("unsafe SMTP configuration accepted")
		}
	}
}
