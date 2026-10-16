package authprivacy

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/mail"
	"net/smtp"
	"net/textproto"
	"strings"
	"time"
)

type SMTPConfig struct {
	Address    string
	ServerName string
	From       string
	Username   string
	Password   string
	TLSConfig  *tls.Config
	Timeout    time.Duration
	// Only a literal loopback address can opt out of STARTTLS, for local tests.
	AllowInsecureLoopback bool
}

type SMTPProvider struct {
	config SMTPConfig
	host   string
}

func NewSMTPProvider(config SMTPConfig) (*SMTPProvider, error) {
	host, port, err := net.SplitHostPort(config.Address)
	if err != nil || host == "" || port == "" || config.Timeout <= 0 || config.Timeout > 30*time.Second {
		return nil, errors.New("invalid SMTP configuration")
	}
	from, err := mail.ParseAddress(config.From)
	if err != nil || from.Name != "" || from.Address != config.From || strings.IndexAny(config.From, "\r\n") >= 0 {
		return nil, errors.New("invalid SMTP sender")
	}
	if config.AllowInsecureLoopback {
		ip := net.ParseIP(host)
		if ip == nil || !ip.IsLoopback() || config.Username != "" || config.Password != "" {
			return nil, errors.New("insecure SMTP is limited to unauthenticated literal loopback tests")
		}
	}
	if config.TLSConfig != nil {
		// tls.Config.Clone is shallow for trust pools. Copy those too so later
		// caller mutation cannot change this provider's certificate policy.
		owned := config.TLSConfig.Clone()
		if owned.InsecureSkipVerify {
			return nil, errors.New("SMTP certificate verification cannot be disabled")
		}
		if owned.RootCAs != nil {
			owned.RootCAs = owned.RootCAs.Clone()
		}
		if owned.ClientCAs != nil {
			owned.ClientCAs = owned.ClientCAs.Clone()
		}
		config.TLSConfig = owned
	}
	if config.ServerName == "" {
		config.ServerName = host
	}
	return &SMTPProvider{config: config, host: host}, nil
}

// SendOTP makes one SMTP attempt. It never treats Message-ID as SMTP deduplication.
// The Eligibility durable dispatch claim is responsible for preventing repeats.
func (p *SMTPProvider) SendOTP(ctx context.Context, operation [32]byte, email, code string) (MailOutcome, error) {
	if p.config.TLSConfig != nil && p.config.TLSConfig.InsecureSkipVerify {
		return MailNotSent, errors.New("SMTP certificate verification cannot be disabled")
	}
	if err := validateCampusEmail(email); err != nil {
		return MailNotSent, errors.New("invalid SMTP recipient")
	}
	if !validOTPShape(code) {
		return MailNotSent, errors.New("invalid SMTP OTP payload")
	}
	dialer := net.Dialer{Timeout: p.config.Timeout}
	conn, err := dialer.DialContext(ctx, "tcp", p.config.Address)
	if err != nil {
		return MailNotSent, errors.New("SMTP connection unavailable")
	}
	defer conn.Close()
	deadline := time.Now().Add(p.config.Timeout)
	if callerDeadline, ok := ctx.Deadline(); ok && callerDeadline.Before(deadline) {
		deadline = callerDeadline
	}
	if err = conn.SetDeadline(deadline); err != nil {
		return MailNotSent, errors.New("SMTP deadline unavailable")
	}
	stop := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer stop()
	client, err := smtp.NewClient(conn, p.host)
	if err != nil {
		return MailNotSent, errors.New("SMTP greeting unavailable")
	}
	defer client.Close()
	if !p.config.AllowInsecureLoopback {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return MailNotSent, errors.New("SMTP requires STARTTLS")
		}
		tlsConfig := &tls.Config{ServerName: p.config.ServerName, MinVersion: tls.VersionTLS12}
		if p.config.TLSConfig != nil {
			tlsConfig = p.config.TLSConfig.Clone()
			tlsConfig.ServerName = p.config.ServerName
			if tlsConfig.MinVersion < tls.VersionTLS12 {
				tlsConfig.MinVersion = tls.VersionTLS12
			}
		}
		if err = client.StartTLS(tlsConfig); err != nil {
			return MailNotSent, errors.New("SMTP TLS unavailable")
		}
		if p.config.Username != "" || p.config.Password != "" {
			if err = client.Auth(smtp.PlainAuth("", p.config.Username, p.config.Password, p.host)); err != nil {
				return MailNotSent, errors.New("SMTP authentication unavailable")
			}
		}
	}
	if err = client.Mail(p.config.From); err != nil {
		return MailNotSent, errors.New("SMTP sender rejected")
	}
	if err = client.Rcpt(email); err != nil {
		return MailNotSent, errors.New("SMTP recipient rejected")
	}
	writer, err := client.Data()
	if err != nil {
		return MailNotSent, errors.New("SMTP DATA not started")
	}
	domain := p.config.From[strings.LastIndex(p.config.From, "@")+1:]
	var message bytes.Buffer
	fmt.Fprintf(&message, "From: %s\r\nTo: %s\r\nSubject: Hnuhole verification code\r\nMessage-ID: <%s@%s>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nYour Hnuhole campus verification code is %s.\r\nIt expires in five minutes.\r\n", p.config.From, email, hex.EncodeToString(operation[:]), domain, code)
	if _, err = io.Copy(writer, &message); err != nil {
		return MailUnknown, errors.New("SMTP DATA outcome unknown")
	}
	// Once DATA has been written, loss of the final reply is unknown even when
	// the local socket closes successfully. Never automatically submit it again.
	if err = writer.Close(); err != nil {
		var response *textproto.Error
		if errors.As(err, &response) && response.Code >= 400 && response.Code <= 599 {
			// A complete negative DATA reply definitively rejects this message.
			// Only absent or malformed replies leave delivery uncertain.
			return MailNotSent, errors.New("SMTP payload rejected")
		}
		return MailUnknown, errors.New("SMTP acceptance outcome unknown")
	}
	_ = client.Quit() // final DATA success already established acceptance.
	return MailSent, nil
}
