package postmedia

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

// Validator is a server-side byte inspection boundary, never a viewer codec.
type Validator interface {
	Inspect(context.Context, []byte) (Metadata, error)
}

// ProcessValidator uses the existing Pillow/libwebp implementation in a bounded
// Linux child, without rewriting animation or importing a new Flutter decoder.
// The trusted program and helper must be supplied explicitly at startup.
type ProcessValidator struct {
	python, script string
	scriptHash     [32]byte
	slots          chan struct{}
}

func NewProcessValidator(python, script, scriptSHA256 string) (*ProcessValidator, error) {
	if runtime.GOOS != "linux" || !filepath.IsAbs(python) || !filepath.IsAbs(script) {
		return nil, ErrUnavailable
	}
	for _, p := range []string{python, script} {
		info, e := os.Stat(p)
		if e != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0022 != 0 {
			return nil, ErrUnavailable
		}
	}
	data, e := os.ReadFile(script)
	if e != nil || len(data) > 65536 {
		return nil, ErrUnavailable
	}
	h := sha256.Sum256(data)
	if hex.EncodeToString(h[:]) != scriptSHA256 {
		return nil, ErrUnavailable
	}
	v := &ProcessValidator{python: python, script: script, scriptHash: h, slots: make(chan struct{}, 2)}
	// No image or service credential is used for the startup dependency probe.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, python, "-I", "-B", script, "--probe")
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C.UTF-8"}
	out, e := cmd.Output()
	if e != nil || string(out) != "postmedia-validator/v1\n" {
		return nil, ErrUnavailable
	}
	return v, nil
}

func (v *ProcessValidator) Inspect(ctx context.Context, data []byte) (Metadata, error) {
	var m Metadata
	if len(data) < 1 || len(data) > MaxBytes {
		return m, ErrInvalid
	}
	select {
	case v.slots <- struct{}{}:
		defer func() { <-v.slots }()
	case <-ctx.Done():
		return m, ErrUnavailable
	}
	// Refuse a helper changed after startup; operational updates require restart.
	source, e := os.ReadFile(v.script)
	if e != nil || sha256.Sum256(source) != v.scriptHash {
		return m, ErrUnavailable
	}
	child, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(child, v.python, "-I", "-B", v.script)
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C.UTF-8"}
	cmd.Stdin = bytes.NewReader(data)
	var out limitedOutput
	cmd.Stdout = &out
	cmd.Stderr = io.Discard
	e = cmd.Run()
	if e != nil {
		if exit, ok := e.(*exec.ExitError); ok && exit.ExitCode() == 2 {
			return m, ErrInvalid
		}
		return m, ErrUnavailable
	}
	d := json.NewDecoder(bytes.NewReader(out.Bytes()))
	d.DisallowUnknownFields()
	if d.Decode(&m) != nil || d.Decode(new(any)) != io.EOF {
		return Metadata{}, ErrUnavailable
	}
	return m, nil
}

type limitedOutput struct{ bytes.Buffer }

func (b *limitedOutput) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 2048 {
		return 0, ErrUnavailable
	}
	return b.Buffer.Write(p)
}

// Thumbnailer is optional so legacy validators can keep their original-only
// contract. The HTTP manifest advertises previews only after explicit opt-in.
type Thumbnailer interface {
	Thumbnail(context.Context, []byte) ([]byte, error)
}

func (v *ProcessValidator) Thumbnail(ctx context.Context, data []byte) ([]byte, error) {
	if len(data) < 1 || len(data) > MaxBytes {
		return nil, ErrInvalid
	}
	select {
	case v.slots <- struct{}{}:
		defer func() { <-v.slots }()
	case <-ctx.Done():
		return nil, ErrUnavailable
	}
	source, e := os.ReadFile(v.script)
	if e != nil || sha256.Sum256(source) != v.scriptHash {
		return nil, ErrUnavailable
	}
	child, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(child, v.python, "-I", "-B", v.script, "--thumbnail")
	cmd.Env = []string{"PATH=/usr/bin:/bin", "LANG=C.UTF-8"}
	cmd.Stdin = bytes.NewReader(data)
	var out thumbnailOutput
	cmd.Stdout, cmd.Stderr = &out, io.Discard
	if cmd.Run() != nil {
		return nil, ErrUnavailable
	}
	b := out.Bytes()
	if len(b) < 12 || string(b[:4]) != "RIFF" || string(b[8:12]) != "WEBP" {
		return nil, ErrUnavailable
	}
	return b, nil
}

type thumbnailOutput struct{ bytes.Buffer }

func (b *thumbnailOutput) Write(p []byte) (int, error) {
	if b.Len()+len(p) > MaxThumbnailBytes {
		return 0, ErrUnavailable
	}
	return b.Buffer.Write(p)
}
