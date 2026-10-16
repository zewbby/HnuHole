package authprivacy

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// AuthorizationEvidence is a signed, independently held time/recovery sample.
// File providers and signers are test infrastructure, not production time or
// independent operator services. Domain binds a sample to one party's auth domain.
type AuthorizationEvidence struct {
	Domain     string    `json:"domain"`
	Version    uint64    `json:"version"`
	Generation uint64    `json:"generation"`
	IssuedAt   time.Time `json:"issuedAt"`
	ValidUntil time.Time `json:"validUntil"`
	TrustedAt  time.Time `json:"trustedAt"`
}

type SignedAuthorizationEvidence struct {
	Evidence  AuthorizationEvidence `json:"evidence"`
	Signature []byte                `json:"signature"`
}

func SignAuthorizationEvidence(key ed25519.PrivateKey, e AuthorizationEvidence) (SignedAuthorizationEvidence, error) {
	if len(key) != ed25519.PrivateKeySize {
		return SignedAuthorizationEvidence{}, errors.New("invalid evidence signer")
	}
	e.IssuedAt, e.ValidUntil, e.TrustedAt = e.IssuedAt.UTC(), e.ValidUntil.UTC(), e.TrustedAt.UTC()
	message, err := json.Marshal(e)
	if err != nil {
		return SignedAuthorizationEvidence{}, err
	}
	return SignedAuthorizationEvidence{Evidence: e, Signature: ed25519.Sign(key, message)}, nil
}

type AuthorizationEvidenceProvider interface {
	Current(context.Context) (SignedAuthorizationEvidence, error)
}

// FileAuthorizationEvidenceProvider is a controllable DB-external lab source.
// The verifier never trusts its file contents without checking the signature.
type FileAuthorizationEvidenceProvider struct{ Path string }

func NewFileAuthorizationEvidenceProvider(path string) *FileAuthorizationEvidenceProvider {
	return &FileAuthorizationEvidenceProvider{Path: path}
}

func (p *FileAuthorizationEvidenceProvider) Current(ctx context.Context) (SignedAuthorizationEvidence, error) {
	if err := ctx.Err(); err != nil {
		return SignedAuthorizationEvidence{}, err
	}
	raw, err := readAuthorizationFile(p.Path, 4096)
	if err != nil {
		return SignedAuthorizationEvidence{}, err
	}
	var signed SignedAuthorizationEvidence
	if err = json.Unmarshal(raw, &signed); err != nil {
		return SignedAuthorizationEvidence{}, err
	}
	return signed, nil
}

func (p *FileAuthorizationEvidenceProvider) Store(ctx context.Context, signed SignedAuthorizationEvidence) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	raw, err := json.Marshal(signed)
	if err != nil {
		return err
	}
	return writeFileAtomic(p.Path, raw)
}

// authorizationAnchor remains outside database snapshots. It is monotonically
// advanced before a database authorization commit; an interrupted commit may
// require explicit recovery, but must never grant authority from a stale DB.
type authorizationAnchor struct {
	Domain          string                       `json:"domain"`
	Generation      uint64                       `json:"generation"`
	Version         uint64                       `json:"version"`
	Highwater       time.Time                    `json:"highwater"`
	Frozen          bool                         `json:"frozen"`
	OfflineEvidence *SignedAuthorizationEvidence `json:"offlineEvidence,omitempty"`
}

type signedAuthorizationAnchor struct {
	Anchor    authorizationAnchor `json:"anchor"`
	Signature []byte              `json:"signature"`
}

type FileAuthorizationAnchorStore struct {
	Path   string
	signer ed25519.PrivateKey
	public ed25519.PublicKey
}

func NewFileAuthorizationAnchorStore(path string, key ed25519.PrivateKey) (*FileAuthorizationAnchorStore, error) {
	if path == "" || len(key) != ed25519.PrivateKeySize {
		return nil, errors.New("invalid independent authorization anchor")
	}
	private := append(ed25519.PrivateKey(nil), key...)
	return &FileAuthorizationAnchorStore{Path: path, signer: private, public: private.Public().(ed25519.PublicKey)}, nil
}

// withLocked serializes all gate instances sharing this anchor, including
// instances in other processes. Callers lock the database gate row first.
func (s *FileAuthorizationAnchorStore) withLocked(fn func(*authorizationAnchor, bool) error) error {
	lockFile, err := os.OpenFile(s.Path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lockFile.Close()
	if err = syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
	a, exists, err := s.readLocked()
	if err != nil {
		return err
	}
	return fn(&a, exists)
}

func (s *FileAuthorizationAnchorStore) readLocked() (authorizationAnchor, bool, error) {
	raw, err := readAuthorizationFile(s.Path, 8192)
	if errors.Is(err, os.ErrNotExist) {
		return authorizationAnchor{}, false, nil
	}
	if err != nil {
		return authorizationAnchor{}, false, err
	}
	var signed signedAuthorizationAnchor
	if err = json.Unmarshal(raw, &signed); err != nil {
		return authorizationAnchor{}, false, err
	}
	message, err := json.Marshal(signed.Anchor)
	if err != nil || !ed25519.Verify(s.public, message, signed.Signature) {
		return authorizationAnchor{}, false, errors.New("invalid independent anchor signature")
	}
	return signed.Anchor, true, nil
}

func readAuthorizationFile(path string, max int64) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, max+1))
	if err != nil {
		return nil, err
	}
	if int64(len(raw)) > max {
		return nil, errors.New("authorization evidence file too large")
	}
	return raw, nil
}

func (s *FileAuthorizationAnchorStore) writeLocked(a authorizationAnchor) error {
	a.Highwater = a.Highwater.UTC()
	message, err := json.Marshal(a)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(signedAuthorizationAnchor{Anchor: a, Signature: ed25519.Sign(s.signer, message)})
	if err != nil {
		return err
	}
	return writeFileAtomic(s.Path, raw)
}

func writeFileAtomic(path string, raw []byte) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, ".authgate-*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if err = temp.Chmod(0600); err == nil {
		_, err = temp.Write(raw)
	}
	if err == nil {
		err = temp.Sync()
	}
	if closeErr := temp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err = os.Rename(temp.Name(), path); err != nil {
		return err
	}
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer d.Close()
	if err = d.Sync(); err != nil {
		return fmt.Errorf("sync independent anchor directory: %w", err)
	}
	return nil
}

func equalSignedAuthorizationEvidence(a, b SignedAuthorizationEvidence) bool {
	x, errX := json.Marshal(a.Evidence)
	y, errY := json.Marshal(b.Evidence)
	return errX == nil && errY == nil && bytes.Equal(x, y) && bytes.Equal(a.Signature, b.Signature)
}
