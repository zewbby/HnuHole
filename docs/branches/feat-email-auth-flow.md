# AUTH-EMAIL-LOGIN-01：真实校邮注册与已有账号登录

2026-10-21；分支 `feat/email-auth-flow`，基线 `76af92b`；包括本线程 AUTH-SMTP-01 依赖。按用户要求分支不带codex。

## 状态与范围

实现完成，独立同事审查三项已修并复核；尚未合并，已加载本机WSL开发服务并在vivo限定验收，未正式发布。当前需求与协议见[需求报告](../design/email-login-requirements-20261021.md)。旧独立需求报告工作区不改动。

范围：A02运行配置/SMTP、A03/A06会话授权、A12/B01客户端认证入口；注册的用户名密码/恢复码由用户本人完成。新增V登录专用取码/确认、227字节环境和原操作绑定签名、C既有账号登录；用途隔离、幂等/过期、单会话/Gate/封禁注销复用、原生待办恢复、最小过期墓碑；密码10–128可见ASCII且旧凭据仍可验证；按用户删除冗余说明与统一“发送验证码”。

代码入口：`services/api/internal/authprivacy/{eligibility_email_login,community_email_login}.go`、`protocol/email_login.go`、`internal/authprivacyhttp/email_login_endpoints.go`、`internal/authprivacyruntime/smtp_config.go`、正式V迁移0005/0006和受限grant；`apps/mobile/lib/src/auth/`；私有配置向导 `tools/smtp/`。新HTTP契约已同步C/V OpenAPI。

## 已执行验证

- WSL Go1.22.2，`services/api` 下 `go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...` PASS（宿主通过不代证SQL）。
- `PGPORT=55445 sh authlab/run-email-login-isolated.sh` PASS：本任务新建的一次性私有socket PostgreSQL、全正式迁移，`go test -race -count=1 -p 1 ./internal/authprivacy -run '^Test(EmailLogin|Password|Session)'`。覆盖原账号、错误/跨用途OTP、确认重放、同键并发只建一个会话、旧会话接替、未注册不建号/不占配额、过期最小墓碑、10位/标点/旧密码、原会话回归。保留首次因旧重设fixture含空格FAIL，fixture按新政策修正后重跑PASS。
- `python3 -B -m unittest discover -s tools/smtp/tests -v` 4 PASS；SMTP专项race PASS，真实TLS/错误主机/未知投递/私有文件及路径边界。授权码从未写入仓库/APK。
- `flutter analyze --no-pub` 0问题；全量原668 PASS，新增邮箱/真实TLS HTTP专项49 PASS，最终全量677 PASS、分析0。覆盖unknown原键重启、确认原码/键、C未知原证明、未注册主动分流、原生写失败、已建会话重放、迟到会话撤销待办、227字节正/225负边界及跨方秘密隔离。
- `python -X utf8 packages/openapi/check-specs.py` 全部11份规范与契约 PASS。
- Vivo V2323A/Android15／序列10CEAG17RY003M7：App真实注册取码→用户校邮收码确认→第二步，后续账号/恢复码由用户亲自完成并确认；后端原槽位ACTIVE。邮箱登录至推荐首页、原账号、唯一有效移动会话、冷启动原生会话恢复 PASS。错误验证码反馈已观察；退出后再次进入原账号也已观察（自动化在计划第二次填码前已见首页，故不额外声称该段完整动作均由脚本执行）。未取得用户密码/恢复码，不放入任何测试记录。

## 独立审查与运营边界

独立agent只读审查（非GitHub成员批准）：首次发现227/225证明长度、迟到会话撤销缺少持久化、V过期记录保留过多；均修复并补自动回归，定点复核无新增代码阻断；随后补C/V正式OpenAPI路径。

WSL升级前做V私有pg_dump、配置备份；仅前向迁移、替换C/V二进制，未reset共享库。旧authdev不识别SMTP字段导致证据watch退出/V冻结；已升级同源authdev并签名恢复，服务ready。测试USB loopback需要电脑/WSL/USB在线；公网试用不可沿用失效trycloudflare入口。临时OTP观察通道只服务用户指定测试邮箱、QQ真实确认接收、原码仅内存且600 socket一次读取，结束后已恢复QQ直连并关闭，最终V就绪PASS。

未验：iOS、正式部署、独立第三方安全/运营证据、所有设备矩阵和完整双机接替；未升级A02/A03/A06/A12整模块结论。真实校园邮箱人工收件确认仅沿用本轮用户确认，不将出站观察误写为再次人工确认。

证据：[机器摘要](../design/validation/email-auth-20261021/verification.json)；交接 [HANDOFF](../design/HANDOFF.md)、[progress](../design/progress.md)、[模块表](../design/module-acceptance-handoff.md)、[台账](../design/module-acceptance-ledger.json)。下一步：最终检查/提交PR与CI；合并后同签主体APK交付。
