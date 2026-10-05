// authdev holds same-machine development operator authority. It is never part
// of either public service and cannot establish production time independence.
package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
)

type operatorConfig struct {
	Service                      authprivacyhttp.Service `json:"service,omitempty"`
	CommunityConfig              string                  `json:"communityConfig"`
	VerifierConfig               string                  `json:"verifierConfig,omitempty"`
	RecoveryDatabaseURL          string                  `json:"recoveryDatabaseUrl"`
	RecoveryDatabasePasswordFile string                  `json:"recoveryDatabasePasswordFile"`
	EvidenceKeyFile              string                  `json:"evidenceKeyFile"`
	RecoveryKeyFile              string                  `json:"recoveryKeyFile"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: authdev init|issue|recover|freeze -dir/-operator")
		os.Exit(1)
	}
	var err error
	switch os.Args[1] {
	case "init":
		err = initialize(os.Args[2:])
	case "issue", "recover", "freeze":
		err = operate(os.Args[1], os.Args[2:])
	case "watch":
		err = watch(os.Args[2:])
	default:
		err = errors.New("unknown development command")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "authdev:", err)
		os.Exit(1)
	}
}
func save(path string, b []byte) error { return os.WriteFile(path, b, 0600) }
func saveJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return save(path, append(b, '\n'))
}
func generateKey(dir, name string) error {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	if err = save(filepath.Join(dir, name+".key"), priv); err != nil {
		return err
	}
	return save(filepath.Join(dir, name+".pub"), pub)
}
func randomMaterial(dir, name string, password bool) error {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return err
	}
	if password {
		b = []byte(hex.EncodeToString(b))
	}
	return save(filepath.Join(dir, name), b)
}

func initialize(args []string) error {
	f := flag.NewFlagSet("init", flag.ContinueOnError)
	dir := f.String("dir", "", "new private development directory (must not exist)")
	cPort := f.Int("community-port", 8443, "C public HTTPS port")
	vPort := f.Int("verifier-port", 8444, "V public HTTPS port")
	ciPort := f.Int("community-internal-port", 9443, "C internal mTLS port")
	viPort := f.Int("verifier-internal-port", 9444, "V internal mTLS port")
	smtp := f.Int("smtp-port", 1025, "literal loopback Mailpit SMTP port")
	cd := f.String("community-dsn", "postgres://hnuhole_c_runtime@127.0.0.1:55432/hnuhole_c?sslmode=disable", "C runtime DSN without password")
	vd := f.String("verifier-dsn", "postgres://hnuhole_v_runtime@127.0.0.1:55433/hnuhole_v?sslmode=disable", "V runtime DSN without password")
	rd := f.String("recovery-dsn", "postgres://hnuhole_c_recovery@127.0.0.1:55432/hnuhole_c?sslmode=disable", "separate recovery DSN without password")
	vr := f.String("verifier-recovery-dsn", "postgres://hnuhole_v_recovery@127.0.0.1:55433/hnuhole_v?sslmode=disable", "separate V recovery DSN without password")
	rp := f.String("webauthn-rp-id", "", "explicit trusted RP ID; empty leaves Passkey disabled")
	httpsOrigins := f.String("webauthn-https-origins", "", "comma-separated fixed WebAuthn HTTPS origins, independently provisioned")
	androidOrigins := f.String("webauthn-android-origins", "", "comma-separated trusted Android APK signing origins")
	if err := f.Parse(args); err != nil {
		return err
	}
	if f.NArg() != 0 {
		return errors.New("unexpected initialization arguments")
	}
	if *dir == "" {
		return errors.New("-dir is required")
	}
	webAuthn, err := developmentWebAuthnPolicy(*rp, *httpsOrigins, *androidOrigins)
	if err != nil {
		return err
	}
	seenPorts := map[int]bool{}
	for _, port := range []int{*cPort, *vPort, *ciPort, *viPort, *smtp} {
		if port < 1024 || port > 65535 || seenPorts[port] {
			return errors.New("invalid or duplicate development port")
		}
		seenPorts[port] = true
	}
	abs, err := filepath.Abs(*dir)
	if err != nil {
		return err
	}
	if err = os.Mkdir(abs, 0700); err != nil {
		return errors.New("development directory must be new")
	}
	if err = os.Mkdir(filepath.Join(abs, "operator"), 0700); err != nil {
		return err
	}
	// Independent C/V protocol, anchor, evidence, recovery and break-glass keys.
	for _, name := range []string{"c-signing", "v-signing", "c-anchor", "v-anchor", "operator/evidence", "operator/recovery", "operator/breakglass", "operator/v-evidence", "operator/v-recovery", "operator/v-breakglass"} {
		if err = generateKey(abs, name); err != nil {
			return err
		}
	}
	for _, name := range []string{"c-network.key", "v-network.key", "c-request.key", "v-address-lock.key", "v-otp.key", "v-mail.key", "v-request-hmac.key", "v-limit.key"} {
		if err = randomMaterial(abs, name, false); err != nil {
			return err
		}
	}
	for _, name := range []string{"db-c-runtime.password", "db-v-runtime.password", "operator/db-c-recovery.password", "operator/db-v-recovery.password", "operator/db-c-migrator.password", "operator/db-v-migrator.password", "operator/db-c-admin.password", "operator/db-v-admin.password"} {
		if err = randomMaterial(abs, name, true); err != nil {
			return err
		}
	}
	for _, party := range []string{"c", "v"} {
		for _, name := range []string{"evidence", "recovery", "breakglass"} {
			operatorName := name
			if party == "v" {
				operatorName = "v-" + name
			}
			b, err := os.ReadFile(filepath.Join(abs, "operator", operatorName+".pub"))
			if err != nil {
				return err
			}
			if err = save(filepath.Join(abs, party+"-"+name+".pub"), b); err != nil {
				return err
			}
		}
	}
	// ECDSA P-256 leaves are compatible with the existing Dart TLS path. The
	// protocol signatures remain Ed25519 and are separate from TLS keys.
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	ca := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Hnuhole same-machine DEV root"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(30 * 24 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
	caDER, err := x509.CreateCertificate(rand.Reader, ca, ca, &caKey.PublicKey, caKey)
	if err != nil {
		return err
	}
	ca, err = x509.ParseCertificate(caDER)
	if err != nil {
		return err
	}
	if err = save(filepath.Join(abs, "dev-ca.pem"), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})); err != nil {
		return err
	}
	caPrivate, err := x509.MarshalPKCS8PrivateKey(caKey)
	if err != nil {
		return err
	}
	if err = save(filepath.Join(abs, "operator", "dev-ca.key"), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: caPrivate})); err != nil {
		return err
	}
	for i, party := range []authprivacyhttp.Service{authprivacyhttp.CommunityService, authprivacyhttp.VerifierService} {
		for j, kind := range []string{"public", "internal"} {
			key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
			if err != nil {
				return err
			}
			identity, err := authprivacyhttp.IdentityURI("dev", party)
			if err != nil {
				return err
			}
			leaf := &x509.Certificate{SerialNumber: big.NewInt(int64(10 + i*2 + j)), Subject: pkix.Name{CommonName: "DEV " + string(party) + " " + kind}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(7 * 24 * time.Hour), DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")}, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
			if kind == "internal" {
				leaf.URIs = append(leaf.URIs, identity)
				leaf.ExtKeyUsage = append(leaf.ExtKeyUsage, x509.ExtKeyUsageClientAuth)
			}
			der, err := x509.CreateCertificate(rand.Reader, leaf, ca, &key.PublicKey, caKey)
			if err != nil {
				return err
			}
			private, err := x509.MarshalPKCS8PrivateKey(key)
			if err != nil {
				return err
			}
			prefix := "c"
			if party == authprivacyhttp.VerifierService {
				prefix = "v"
			}
			if err = save(filepath.Join(abs, prefix+"-"+kind+".pem"), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})); err != nil {
				return err
			}
			if err = save(filepath.Join(abs, prefix+"-"+kind+".key"), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: private})); err != nil {
				return err
			}
		}
	}
	if err = save(filepath.Join(abs, "dev-password-blocklist.txt"), []byte("passwordpassword\n123456789012345\ncorrecthorsebatterystaple\n")); err != nil {
		return err
	}
	base := func(party string, port, internal, peer int, dsn string) authprivacyruntime.Config {
		return authprivacyruntime.Config{Environment: "dev", DatabaseURL: dsn, DatabasePasswordFile: "db-" + party + "-runtime.password", PublicListen: fmt.Sprintf("127.0.0.1:%d", port), InternalListen: fmt.Sprintf("127.0.0.1:%d", internal), PublicOrigin: fmt.Sprintf("https://127.0.0.1:%d", port), PeerOrigin: fmt.Sprintf("https://127.0.0.1:%d", peer), CAFile: "dev-ca.pem", PublicCertificateFile: party + "-public.pem", PublicKeyFile: party + "-public.key", InternalCertificateFile: party + "-internal.pem", InternalKeyFile: party + "-internal.key", NetworkKeyFile: party + "-network.key", SigningKeyFile: party + "-signing.key", TrustedCommunityKeyFile: "c-signing.pub", TrustedVerifierKeyFile: "v-signing.pub", RequestTimeoutSeconds: 30, SQLTimeoutSeconds: 10, ShutdownTimeoutSeconds: 20, WorkerBatch: 16, WorkerTimeoutSeconds: 15, WorkerIntervalSeconds: 2, PasswordWorkers: 2, NetworkMutationCapacity: 120, NetworkQueryCapacity: 240, NetworkMaxEntries: 4096}
	}
	c := base("c", *cPort, *ciPort, *viPort, *cd)
	v := base("v", *vPort, *viPort, *ciPort, *vd)
	c.AllowedOrigins = []string{c.PublicOrigin, v.PublicOrigin}
	v.AllowedOrigins = append([]string(nil), c.AllowedOrigins...)
	c.RequestKeyFile = "c-request.key"
	c.PasswordBlocklistFile = "dev-password-blocklist.txt"
	c.WebAuthn = webAuthn
	c.Gate = &authprivacyruntime.GateConfig{Domain: "hnuhole-c-dev", EvidenceFile: "c-evidence.json", EvidencePublicKeyFile: "c-evidence.pub", RecoveryPublicKeyFile: "c-recovery.pub", BreakGlassPublicKeyFile: "c-breakglass.pub", AnchorFile: "c-anchor.json", AnchorKeyFile: "c-anchor.key"}
	v.Gate = &authprivacyruntime.GateConfig{Domain: "hnuhole-v-dev", EvidenceFile: "v-evidence.json", EvidencePublicKeyFile: "v-evidence.pub", RecoveryPublicKeyFile: "v-recovery.pub", BreakGlassPublicKeyFile: "v-breakglass.pub", AnchorFile: "v-anchor.json", AnchorKeyFile: "v-anchor.key"}
	c.PeerGatePublicKeyFiles = []string{"v-evidence.pub", "v-recovery.pub", "v-breakglass.pub", "v-anchor.pub"}
	v.PeerGatePublicKeyFiles = []string{"c-evidence.pub", "c-recovery.pub", "c-breakglass.pub", "c-anchor.pub"}
	v.AddressLockKeyFile = "v-address-lock.key"
	v.OTPKeyFile = "v-otp.key"
	v.MailEncryptionKeyFile = "v-mail.key"
	v.RequestHMACKeyFile = "v-request-hmac.key"
	v.LimitKeyFile = "v-limit.key"
	v.SMTPAddress = fmt.Sprintf("127.0.0.1:%d", *smtp)
	v.SMTPFrom = "dev@hnuhole.invalid"
	if err = saveJSON(filepath.Join(abs, "c.json"), c); err != nil {
		return err
	}
	if err = saveJSON(filepath.Join(abs, "v.json"), v); err != nil {
		return err
	}
	op := operatorConfig{CommunityConfig: "../c.json", RecoveryDatabaseURL: *rd, RecoveryDatabasePasswordFile: "db-c-recovery.password", EvidenceKeyFile: "evidence.key", RecoveryKeyFile: "recovery.key"}
	if err = saveJSON(filepath.Join(abs, "operator", "operator.json"), op); err != nil {
		return err
	}
	vop := operatorConfig{Service: authprivacyhttp.VerifierService, VerifierConfig: "../v.json", RecoveryDatabaseURL: *vr, RecoveryDatabasePasswordFile: "db-v-recovery.password", EvidenceKeyFile: "v-evidence.key", RecoveryKeyFile: "v-recovery.key"}
	if err = saveJSON(filepath.Join(abs, "operator", "v-operator.json"), vop); err != nil {
		return err
	}
	fmt.Println("development material created; Gate remains FROZEN until explicit authdev recover")
	return nil
}

func developmentWebAuthnPolicy(rp, httpsOrigins, androidOrigins string) (*authprivacy.WebAuthnConfig, error) {
	if rp == "" && httpsOrigins == "" && androidOrigins == "" {
		return nil, nil
	}
	split := func(raw string) []string {
		if raw == "" {
			return nil
		}
		values := strings.Split(raw, ",")
		for i := range values {
			values[i] = strings.TrimSpace(values[i])
		}
		return values
	}
	policy := &authprivacy.WebAuthnConfig{RPID: rp, Origins: split(httpsOrigins), AndroidOrigins: split(androidOrigins)}
	if _, err := authprivacy.NewWebAuthnValidator(*policy); err != nil {
		return nil, errors.New("explicit WebAuthn RP and signing origins are invalid")
	}
	return policy, nil
}

func operate(command string, args []string) error {
	f := flag.NewFlagSet(command, flag.ContinueOnError)
	path := f.String("operator", "", "private operator JSON")
	validFor := f.Duration("valid-for", 5*time.Minute, "development evidence TTL, maximum five minutes")
	if err := f.Parse(args); err != nil {
		return err
	}
	if f.NArg() != 0 {
		return errors.New("unexpected operator arguments")
	}
	if *validFor < time.Second || *validFor > 5*time.Minute {
		return errors.New("invalid development evidence TTL")
	}
	if *path == "" {
		return errors.New("-operator is required")
	}
	abs, err := filepath.Abs(*path)
	if err != nil {
		return err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 32768 {
		return errors.New("operator file must be private and bounded")
	}
	var op operatorConfig
	file, err := os.Open(abs)
	if err != nil {
		return err
	}
	b, err := io.ReadAll(io.LimitReader(file, 32769))
	_ = file.Close()
	if err != nil || len(b) > 32768 {
		return errors.New("operator JSON too large")
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&op); err != nil || decoder.Decode(new(any)) != io.EOF {
		return errors.New("invalid operator JSON")
	}
	dir := filepath.Dir(abs)
	lock, err := os.OpenFile(filepath.Join(dir, ".operation.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	service := op.Service
	if service == "" {
		service = authprivacyhttp.CommunityService
	}
	party, configPath := "c", op.CommunityConfig
	if service == authprivacyhttp.VerifierService {
		party, configPath = "v", op.VerifierConfig
		if op.CommunityConfig != "" {
			return errors.New("V operator must not possess C configuration")
		}
	} else if service != authprivacyhttp.CommunityService || op.VerifierConfig != "" {
		return errors.New("invalid operator service/configuration")
	}
	c, err := authprivacyruntime.LoadConfig(filepath.Join(dir, configPath), service)
	if err != nil {
		return err
	}
	// Validate purpose-bound operator signers BEFORE connecting or overwriting
	// a previously valid evidence file. Keep these exact loaded bytes for signing.
	var evidenceSigner, recoverySigner ed25519.PrivateKey
	if command != "freeze" {
		evidenceSigner, err = loadBoundOperatorSigner(c, filepath.Join(dir, op.EvidenceKeyFile), c.Gate.EvidencePublicKeyFile)
		if err != nil {
			return err
		}
		if command == "recover" {
			recoverySigner, err = loadBoundOperatorSigner(c, filepath.Join(dir, op.RecoveryKeyFile), c.Gate.RecoveryPublicKeyFile)
			if err != nil {
				return err
			}
		}
	}
	// Copy only the separately permissioned recovery connection into this tool.
	c.DatabaseURL = op.RecoveryDatabaseURL
	c.DatabasePasswordFile = filepath.Join(dir, op.RecoveryDatabasePasswordFile)
	pc, err := c.PoolConfig()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		return errors.New("recovery connection unavailable")
	}
	defer pool.Close()
	var db, user string
	var privileged bool
	if err = pool.QueryRow(ctx, `SELECT current_database(),current_user,(SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls FROM pg_roles WHERE rolname=current_user)`).Scan(&db, &user, &privileged); err != nil || db != "hnuhole_"+party || user != "hnuhole_"+party+"_recovery" || privileged {
		return errors.New("restricted service-bound recovery connection required")
	}
	var excessive bool
	if err = pool.QueryRow(ctx, `SELECT pg_has_role(current_user,$1::text,'MEMBER') OR has_database_privilege(current_user,current_database(),'CREATE,TEMP') OR has_schema_privilege(current_user,$2::text,'CREATE') OR has_schema_privilege(current_user,'public','CREATE') OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=$2::text AND c.relkind IN ('r','p') AND c.relname NOT IN ('authorization_gate','authorization_gate_audit') AND has_table_privilege(current_user,c.oid,'SELECT,INSERT,UPDATE,DELETE'))`, "hnuhole_"+party+"_owner", party+"_auth").Scan(&excessive); err != nil || excessive {
		return errors.New("recovery role must be limited to its Gate and audit")
	}
	gate, err := authprivacyruntime.NewGate(c, pool, service)
	if err != nil {
		return err
	}
	if command == "freeze" {
		if err = gate.Freeze(ctx, "EXPLICIT_DEV_FREEZE"); err != nil {
			return err
		}
		fmt.Println("development Gate frozen")
		return nil
	}
	var generation, version int64
	if err = pool.QueryRow(ctx, `SELECT authorization_generation,evidence_version FROM `+party+`_auth.authorization_gate WHERE singleton_id=1`).Scan(&generation, &version); err != nil {
		return errors.New("read Gate checkpoint failed")
	}
	// Recover must advance both DB and any external checkpoint. Read only the
	// signed fields here; Recover itself verifies the signature and monotonicity.
	if anchor, err := os.ReadFile(c.Path(c.Gate.AnchorFile)); err == nil {
		var a struct {
			Anchor struct {
				Generation uint64 `json:"generation"`
				Version    uint64 `json:"version"`
			} `json:"anchor"`
		}
		if json.Unmarshal(anchor, &a) == nil {
			if int64(a.Anchor.Generation) > generation {
				generation = int64(a.Anchor.Generation)
			}
			if int64(a.Anchor.Version) > version {
				version = int64(a.Anchor.Version)
			}
		}
	}
	if command == "recover" {
		generation++
	}
	if generation < 1 {
		return errors.New("Gate must be explicitly recovered before evidence renewal")
	}
	version++
	at := time.Now().UTC().Truncate(time.Microsecond)
	signed, err := authprivacy.SignAuthorizationEvidence(evidenceSigner, authprivacy.AuthorizationEvidence{Domain: c.Gate.Domain, Version: uint64(version), Generation: uint64(generation), IssuedAt: at, TrustedAt: at, ValidUntil: at.Add(*validFor)})
	if err != nil {
		return err
	}
	if err = authprivacy.NewFileAuthorizationEvidenceProvider(c.Path(c.Gate.EvidenceFile)).Store(ctx, signed); err != nil {
		return err
	}
	if command == "recover" {
		request, err := authprivacy.SignAuthorizationRecovery(recoverySigner, authprivacy.AuthorizationRecoveryRequest{Role: "authorization-recovery", Actor: "same-machine-dev-operator", Reason: "explicit development recovery", OperationID: uuid.NewString(), Mode: authprivacy.AuthorizationRecoveryNormal, Evidence: signed})
		if err != nil {
			return err
		}
		if err = gate.Recover(ctx, request); err != nil {
			return err
		}
	}
	fmt.Println("development signed evidence updated")
	return nil
}
func readPrivate(path string) (ed25519.PrivateKey, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() != 64 {
		return nil, errors.New("invalid private operator key")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, errors.New("operator key unavailable")
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 65))
	if err != nil || len(b) != 64 || !bytes.Equal(ed25519.NewKeyFromSeed(b[:32]), b) {
		return nil, errors.New("invalid operator signer seed/public shape")
	}
	return ed25519.PrivateKey(b), nil
}

func watch(args []string) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := operate("issue", args); err != nil {
				return err
			}
		}
	}
}

func loadBoundOperatorSigner(c authprivacyruntime.Config, path, publicPath string) (ed25519.PrivateKey, error) {
	key, err := readPrivate(path)
	if err != nil {
		return nil, err
	}
	public, err := c.PublicKey(publicPath)
	if err != nil || !bytes.Equal(key.Public().(ed25519.PublicKey), public) {
		return nil, errors.New("operator signer purpose/trust mismatch")
	}
	return key, nil
}
