package authprivacyhttp

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"os"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// The shipped Dart transport talks to the actual C handlers and isolated PG.
// A compiled probe is opt-in locally; feed-ui CI supplies it explicitly.
func TestRealHTTPSFeedDartPostgres(t *testing.T) {
	probe := os.Getenv("FEED_DART_PROBE")
	if probe == "" {
		t.Skip("compiled feed Dart probe absent")
	}
	s := e2eNewServices(t)
	certificate := mobileLabCertificate(t)
	tlsConfig, err := PublicTLSConfig(certificate)
	if err != nil {
		t.Fatal(err)
	}
	s.cPublic = e2eServer(t, s.cPublic.Config.Handler, tlsConfig)
	transport := s.client.Transport.(*http.Transport).Clone()
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.RootCAs = transport.TLSClientConfig.RootCAs.Clone()
	root, err := x509.ParseCertificate(certificate.Certificate[1])
	if err != nil {
		t.Fatal(err)
	}
	transport.TLSClientConfig.RootCAs.AddCert(root)
	s.client.Transport = transport
	t.Cleanup(transport.CloseIdleConnections)
	owner, _ := e2ePrivacySignup(t, s, "feed_dart_owner")
	reader, _ := e2ePrivacySignup(t, s, "feed_dart_reader")
	catalog := e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/channels", nil, map[string]string{"Authorization": "Bearer " + owner}, 200)
	items := catalog["channels"].([]any)
	channel := items[0].(map[string]any)["id"].(string)
	otherChannel := items[1].(map[string]any)["id"].(string)
	id := postHTTPSIdentity(t, s, owner, "FeedAuthor", 85)
	readerIdentity := postHTTPSIdentity(t, s, reader, "RepostReader", 89)
	var post string
	for _, key := range []byte{86, 87, 88} {
		currentChannel := channel
		if key == 87 {
			currentChannel = otherChannel
		}
		created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, key), owner, "", posts.CreatePostInput{
			ChannelID: currentChannel, IdentityID: id, Title: "真实接口帖子", Body: "仅用于一次性数据库的合成正文"}, 202)
		post = created["postId"].(string)
		if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
			t.Fatal(err)
		}
	}
	certs := s.cPublic.TLS.Certificates[0].Certificate
	rootPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certs[len(certs)-1]})
	fixture := map[string]any{"url": s.cPublic.URL, "certificatePem": string(rootPEM),
		"readerIdentityId": readerIdentity,
		"ownerToken":       owner, "readerToken": reader, "channelId": channel, "postId": post}
	runLiveGovernanceProbe(t, probe, fixture, "feed")
	feed := postHTTPSJSON(t, s, "GET", "/api/v1/feed", reader, "", nil, 200)
	var total float64
	for _, item := range feed["items"].([]any) {
		total += item.(map[string]any)["viewCount"].(float64)
	}
	if total != 1 {
		t.Fatal("Dart view total not committed exactly once")
	}
}
