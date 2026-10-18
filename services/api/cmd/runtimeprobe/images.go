package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type imageProbeState struct {
	CommandKey string `json:"commandKey"`
	TaskID     string `json:"taskId"`
	PostID     string `json:"postId"`
	ChannelID  string `json:"channelId"`
	MediaID    string `json:"mediaId"`
	SHA256     string `json:"sha256"`
	ByteLength int    `json:"byteLength"`
}

// This probe calls the actual C worker and validator, never a publish shortcut.
func (p *probe) images(ctx context.Context, s *state) error {
	if s.Images != nil || s.Posts == nil {
		return errors.New("image probe requires text baseline and no prior image")
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	directory, _, err := p.request(ctx, "GET", p.c, "/api/v1/channels", nil, headers, 200)
	if err != nil {
		return err
	}
	channels, ok := directory["channels"].([]any)
	if !ok {
		return errors.New("image channel directory invalid")
	}
	channelID := ""
	for _, candidate := range channels {
		item, ok := candidate.(map[string]any)
		if !ok {
			return errors.New("image channel record invalid")
		}
		id, e := field(item, "id")
		if e != nil {
			return e
		}
		if id != s.Posts.ChannelID {
			channelID = id
			break
		}
	}
	if channelID == "" {
		return errors.New("separate image channel absent")
	}
	picture := image.NewNRGBA(image.Rect(0, 0, 2, 2))
	picture.SetNRGBA(0, 0, color.NRGBA{R: 180, A: 255})
	picture.SetNRGBA(1, 1, color.NRGBA{B: 200, A: 255})
	var encoded bytes.Buffer
	if err = png.Encode(&encoded, picture); err != nil {
		return err
	}
	data := encoded.Bytes()
	digest := sha256.Sum256(data)
	selection := postmedia.Selection{MediaID: uuid.NewString(), SHA256: hex.EncodeToString(digest[:]), ByteLength: len(data), MIME: "image/png", Width: 2, Height: 2}
	key, err := randomCapability(16)
	if err != nil {
		return err
	}
	accepted, _, err := p.request(ctx, "PUT", p.c, "/api/v1/post-commands/"+key, posts.CreatePostInput{ChannelID: channelID, IdentityID: s.IdentityID, Title: "隔离候选图片", Body: "", Images: []postmedia.Selection{selection}}, headers, 202)
	if err != nil {
		return err
	}
	taskID, err := field(accepted, "taskId")
	if err != nil {
		return err
	}
	postID, err := field(accepted, "postId")
	if err != nil {
		return err
	}
	s.Images = &imageProbeState{CommandKey: key, TaskID: taskID, PostID: postID, ChannelID: channelID, MediaID: selection.MediaID, SHA256: selection.SHA256, ByteLength: len(data)}
	base := "/api/v1/me/post-tasks/" + taskID + "/attempts/1/images/" + selection.MediaID
	grant, _, err := p.request(ctx, "POST", p.c, base+"/upload-grant", nil, headers, 200)
	if err != nil {
		return err
	}
	token, err := field(grant, "uploadToken")
	if err != nil {
		return err
	}
	if _, err = p.imageBytes(ctx, "PUT", base+"/bytes", "Upload "+token, "image/png", data, 204); err != nil {
		return err
	}
	waitState := *s
	waitState.Posts = &postProbeState{TaskID: taskID, PostID: postID}
	if err = p.waitPostPublished(ctx, waitState); err != nil {
		return err
	}
	if err = p.imageSnapshot(ctx, *s); err != nil {
		return err
	}
	group, err := p.imageGroup(ctx, *s)
	if err != nil {
		return err
	}
	_, err = p.imageBytes(ctx, "GET", group.Images[0].Original.Path, "Upload "+token, "", nil, 401)
	return err
}

func (p *probe) imageGroup(ctx context.Context, s state) (postmedia.Group, error) {
	var group postmedia.Group
	if s.Images == nil {
		return group, errors.New("image state absent")
	}
	body, _, err := p.request(ctx, "GET", p.c, "/api/v1/posts/"+s.Images.PostID+"/images", nil, map[string]string{"Authorization": "Bearer " + s.Token}, 200)
	if err != nil {
		return group, err
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return group, err
	}
	if json.Unmarshal(raw, &group) != nil || group.PostID != s.Images.PostID || len(group.Images) != 1 {
		return group, errors.New("image group invalid")
	}
	return group, nil
}

func (p *probe) imageSnapshot(ctx context.Context, s state) error {
	group, err := p.imageGroup(ctx, s)
	if err != nil {
		return err
	}
	i, img := s.Images, group.Images[0]
	expected := "/api/v1/posts/" + i.PostID + "/images/" + img.ContentVersionID + "/original"
	if !postmedia.ValidID(img.ContentVersionID) || img.MediaID != i.MediaID || img.Position != 0 || img.Width != 2 || img.Height != 2 || img.Frames != 1 || img.Animated || !img.SaveAllowed || img.Original.Path != expected || img.Original.MIME != "image/png" || img.Original.ByteLength != i.ByteLength {
		return errors.New("image metadata/resource binding changed")
	}
	data, err := p.imageBytes(ctx, "GET", expected, "Bearer "+s.Token, "", nil, 200)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(data)
	if len(data) != i.ByteLength || hex.EncodeToString(sum[:]) != i.SHA256 {
		return errors.New("original image bytes changed")
	}
	return nil
}

func (p *probe) imageGateRead(ctx context.Context, s state, want int) error {
	if s.Images == nil {
		return nil
	}
	_, _, err := p.request(ctx, "GET", p.c, "/api/v1/posts/"+s.Images.PostID+"/images", nil, map[string]string{"Authorization": "Bearer " + s.Token}, want)
	return err
}

func (p *probe) imageBytes(ctx context.Context, method, path, authorization, mime string, input []byte, want int) ([]byte, error) {
	if !strings.HasPrefix(path, "/api/v1/") || strings.ContainsAny(path, "?#") {
		return nil, errors.New("invalid private image path")
	}
	req, err := http.NewRequestWithContext(ctx, method, strings.TrimSuffix(p.c, "/")+path, bytes.NewReader(input))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", authorization)
	if mime != "" {
		req.Header.Set("Content-Type", mime)
	}
	p.httpsRequests++
	response, err := p.https.Do(req)
	if err != nil {
		return nil, errors.New("image HTTPS transport failed")
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 4097))
	if err != nil || len(data) > 4096 || response.StatusCode != want || response.Header.Get("Cache-Control") != "no-store" || response.Header.Get("X-Request-ID") == "" {
		return nil, errors.New("image response status/size/privacy headers invalid")
	}
	if want == 204 && len(data) != 0 {
		return nil, errors.New("upload response had a body")
	}
	if want == 200 && (response.Header.Get("Content-Type") != "image/png" || response.Header.Get("Content-Disposition") != "attachment" || response.Header.Get("X-Content-Type-Options") != "nosniff" || response.Header.Get("ETag") != "") {
		return nil, errors.New("original image envelope invalid")
	}
	return data, nil
}
