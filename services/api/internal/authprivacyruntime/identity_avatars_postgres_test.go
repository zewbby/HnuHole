package authprivacyruntime

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"testing"
)

func TestIdentityAvatarCommonStartupFencesPostgres(t *testing.T) {
	owner, runtime := moderationStartupLab(t)
	ctx := context.Background()
	for _, tc := range []struct{ breakSQL, repairSQL string }{
		{`REVOKE UPDATE(payload) ON public.identity_avatar_assets FROM hnuhole_c_runtime`, `GRANT UPDATE(payload) ON public.identity_avatar_assets TO hnuhole_c_runtime`},
		{`GRANT UPDATE(digest) ON public.identity_avatar_assets TO hnuhole_c_runtime`, `REVOKE UPDATE(digest) ON public.identity_avatar_assets FROM hnuhole_c_runtime`},
		{`ALTER TABLE public.identity_avatar_assets DISABLE TRIGGER identity_avatar_immutable`, `ALTER TABLE public.identity_avatar_assets ENABLE TRIGGER identity_avatar_immutable`},
		{`ALTER TABLE public.community_identities DISABLE TRIGGER identity_avatar_binding`, `ALTER TABLE public.community_identities ENABLE TRIGGER identity_avatar_binding`},
		{`ALTER TABLE c_auth.accounts DISABLE TRIGGER identity_avatar_account_closed`, `ALTER TABLE c_auth.accounts ENABLE TRIGGER identity_avatar_account_closed`},
		{`GRANT EXECUTE ON FUNCTION public.bind_identity_avatar() TO PUBLIC`, `REVOKE ALL ON FUNCTION public.bind_identity_avatar() FROM PUBLIC`},
	} {
		if _, e := owner.Exec(ctx, tc.breakSQL); e != nil {
			t.Fatal(e)
		}
		if CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService) == nil {
			t.Fatal("avatar startup accepted unsafe boundary")
		}
		if _, e := owner.Exec(ctx, tc.repairSQL); e != nil {
			t.Fatal(e)
		}
		if e := CheckDatabase(ctx, runtime, authprivacyhttp.CommunityService); e != nil {
			t.Fatal("restored avatar boundary rejected", e)
		}
	}
}
