# AUTH-SMTP-01：QQ SMTP 开发接入

> 本子任务已纳入 `feat/email-auth-flow`，原分支重命名；完整范围和最新结果以[整合交接](feat-email-auth-flow.md)为准。下列是SMTP接入时点记录。

- 更新时间：2026-10-21；分支 `feat/smtp-real-delivery`，基线 `76af92b`，实现未提交、未合并；已加载到本机WSL开发V，未正式发布。
- 范围：A02 运行配置与校邮 OTP 投递通道；新增465隐式TLS、显式STARTTLS、私有凭据文件读取、交互配置向导及自动回归。保留默认本地 Mailpit、TLS证书校验、持久投递结果与未知结果不自动重试语义。
- 不包含：既有账号邮箱验证码登录 API、数据库结构或 APK 改动。
- 代码：`services/api/internal/authprivacy/mail.go`、`internal/authprivacyruntime/smtp_config.go`（相对services/api）、`tools/smtp/`。配置入口与操作见 [SMTP说明](../../tools/smtp/README.md)。
- 被测版本：本分支2026-10-21未提交源码。WSL Go1.22.2，已有离线依赖；Python3。
- PASS：`python3 -B -m unittest discover -s tools/smtp/tests -v`（4项）；services/api下 `go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...`；SMTP专项 `go test -mod=readonly -race ./internal/authprivacy ./internal/authprivacyruntime -run SMTP -count=1`。覆盖TLS信任/主机名、认证拒绝、投递未知、私有文件/符号链接拒绝及原配置备份。
- SQL专项 SKIP：未提供隔离DSN；不是真实SQL验收。实际 QQ TLS及认证 PASS；切换前待发队列0／投递中0，原配置私有备份后仅重启V，新二进制TLS就绪 PASS。经用户明确指定的校园邮箱执行一次真实OTP接口，HTTP202、持久mail_outbox状态SENT（QQ接受投递）。校园收件箱实际收到 PASS（2026-10-21用户回复“收到了”）；验证码确认、APK/设备及生产 NOT_RUN。
- 下一步：用户已在本地隐藏输入保存授权码；用户已确认校园邮箱收到真实邮件；下一步继续验证码确认及完整注册流程验收。现阶段不提升A02整模块或生产结论。
- 交接：[HANDOFF](../design/HANDOFF.md)、[progress](../design/progress.md)、[模块交接](../design/module-acceptance-handoff.md)、[台账](../design/module-acceptance-ledger.json)。
