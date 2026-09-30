# 认证隐私隔离实现与验证

用户已授权进入 Phase E；本隔离切片已实现第 0 步 Authorization Safety Gate、用户名密码登录与服务端会话管理，并继续加入恢复码重设、七天注销和恢复凭据管理。代码在 `internal/authprivacy`、`internal/authprivacy/protocol` 与 `internal/authprivacyhttp`。本目录使用独立实验数据库与合成材料；现有 API 主路由、演示认证器和生产 Goose 迁移没有接入这套认证。

校邮与 HTTP 切片的交付见[历史报告](../../../docs/design/auth-privacy-eligibility-http-validation-report.md)；首条数据库切片见[更早报告](../../../docs/design/auth-privacy-isolated-validation-report.md)。`verification.json` 固定首轮证据，`eligibility-http-verification.json` 固定上一轮证据；第 0 步另有新记录。

第 0 步实现与门槛见[Authorization Safety Gate 交付报告](../../../docs/design/auth-authorization-safety-gate-validation-report.md)，机器记录在 `authorization-safety-gate-verification.json`。登录／会话切片见[交付报告](../../../docs/design/auth-privacy-session-lifecycle-validation-report.md)与 `session-lifecycle-verification.json`。历史验证 JSON 保持不改。

恢复码／注销的交付见[历史报告](../../../docs/design/auth-privacy-recovery-closure-validation-report.md)与 `recovery-closure-verification.json`；这些新增服务和端点仍未接入生产。

恢复凭据管理的交付见[本轮报告](../../../docs/design/auth-privacy-recovery-credentials-validation-report.md)与 `recovery-credentials-verification.json`；包含新鲜密码换码和可选WebAuthn绑定／恢复／移除。

## 已实现

- 当前会话＋新鲜密码复验恢复码轮换、五分钟Passkey绑定与固定目标移除；固定ES256／UV／可发现选项／none attestation，随机用户句柄，可发现恢复只签受限重设权限。所有提交继续经Gate并推进统一凭据版本。

- 严格固定消息／编码、Ed25519、公钥导出槽位、bootstrap 持钥证明、当前／上一准入桶。
- 校邮精确字节语法、60 秒发送间隔、最新码、五分钟有效期、设备三错锁五分钟、当前码跨流程／设备十次真错，以及独立发码／验证预算。
- OTP 的独立钥 HMAC、AES-GCM 短期邮件任务；先持久标记外部发送尝试再调用 SMTP。原键不重发，未知 DATA 结果不自动补发。
- 闲置二十四小时的设备风控与无引用地址元数据有界清理；有效锁、未知投递、配额和未决确认仍保留所需证据，不重置仍有数据的邮箱代次。
- OTP 消费、配额、原确认／固定准入桶及待签任务同事务提交；签名器在事务外工作，签名持久后才返回资格。
- 原确认保存旧／新槽位与公钥；推送删退役待办后仍能续办，不再次消费 OTP、不延长原窗口、不清他人新配额。十分钟结果窗口到期后，后台仍处理旧退役，过期资格不能新开户。
- C 原子开户、恢复码完整确认、初始会话和永久结果锚点；重试不重发会话秘密。密码先统一 NFC，执行长度／本地阻止名单／用户名相关弱密码检查，再以受并发限制的 Argon2id 生成验证值。
- 双方公共／内部 HTTP 处理器分开；严格有界 JSON／头／能力解析、独立请求 ID、`no-store`；真实 mTLS 证书链、环境与服务 SAN URI、固定目标与禁止重定向。
- C 收据持久 ACK、迟到 signer／轮换检查、ACK 后清理；已确认终态可只读重签，不复活 outbox 或重启清理时间。
- C 新建 `0002_authorization_gate.sql`：默认 FROZEN 的持久 singleton、高水位、证据版本、授权代次及审计；注册意图与初始会话绑定不可变 authorization_generation。所有注册入口（包括重放）先 Snapshot，最终授权事务统一 CommitAuthorized；已有 Bearer 的隔离认证读入口也经同一门禁。
- 隔离证据由独立于 PostgreSQL 的签名文件提供；独立签名锚点在授权事务提交前推进，旧库快照、丢失／错误证据、时钟回退或冻结状态均 fail closed。正常与离线 break-glass 恢复均需受限角色签名、显式动作、新代次、新鲜证据和审计；离线证据最多 5 分钟有效。该文件机制只是实验替身，不是生产独立授时与外部锚点部署方案。
- C 实验迁移 `0003_session_lifecycle.sql` 增加权威封禁状态、会话撤销原因与仅一条最近接替设备记录。密码验证沿用 NFC／Argon2id 64 MiB／3／4、有界工作池；未知用户名也走相同 KDF 路径。登录在账号锁内复核密码材料／凭据版本，Gate 最终裁决后原子递增会话代次、撤旧建新并只保存无令牌幂等结果；原键重试不给令牌。
- 隔离 C 公共 HTTP 现有注册接口之外新增 `POST /auth/sessions`、`GET /auth/session`、`POST /auth/session-renewals`、`GET /auth/devices` 与 `POST /auth/session-revocations`（完整前缀均为 `/api/v1`）。当前 Bearer 每次从权威账号、封禁、会话代次、撤销／截止和授权代次复核，剩余不超过七天时按同一令牌延至最终可信时间＋三十天；旧设备返回 `401/session_replaced`。独立撤销秘密只撤对应一条会话，重复或记录已清理均 `204`，不读账号或撤新会话。
- 有界清理将登录请求结果收缩为无身份永久墓碑、在服务端最终到期七天后清会话摘要、三十天后清最近替代设备；调用时仍由 Gate 复核。客户端持久登出待办和安全存储仍须在移动端实现。
- `0004_recovery_reset.sql` 建立重设代次、复合活动意图指针、十分钟恢复意图、无秘密结果引用及最小受限事件。当前恢复码证明后首次展示新码，最终锁内复核版本、活动 ID／代次、Gate 与截止，原子更换密码／恢复码、废止全部已存备用凭据和会话；不自动登录、不取消注销、不解除处罚。恢复码三条端点为 `POST /api/v1/auth/recovery-code-reset-intents`、`POST /api/v1/auth/password-resets`、`GET /api/v1/auth/password-reset-result`。
- `0005_account_closure.sql` 建立七天截止和最小状态能力。`POST /api/v1/account-closures` 要求当前 Bearer 与新鲜密码，撤全部会话；`GET /api/v1/account-closures/{closureId}` 只接受独立 `ClosureStatus` 秘密。截止前成功主动密码登录原子取消；到期立即拒绝登录／恢复，worker 原子关闭账号、脱钩槽位并建立 RELEASED outbox。封禁受信命令即时撤会话，只有截止前的新封禁取消申请；禁言可注销，正式关闭终止旧号限制。
- 释放 ACK 在最终 Gate 可信时间下与 ledger／outbox／状态留存起点共事务提交；重复 ACK 不延期。取消状态或持久 ACK 后三十天清状态访问，永久 closureId 锚点拒绝重建申请。密码重设同键重试 `204`，结果查询只返回状态；有界清理先清秘密，再缩结果锚点及删除无引用的终态元数据，受限恢复事件七天清理。未 ACK 状态保留不妨碍八天后收缩原请求 HMAC。

## 复现

需要 Go（模块基线 1.22）与 PostgreSQL 16 或更新版本，`go`、`initdb`、`pg_ctl`、`psql` 在 PATH 中。从本目录执行：

```sh
sh ./run-isolated.sh
```

脚本新建临时集群，只监听 0700 私有 Unix socket，建立两个非超级用户角色／数据库；运行 `go test -race -count=1 -p 1 ./...` 与 `go vet ./...`，结束后停止并删除这个集群。`-p 1` 防止不同测试包同时重建同一实验 schema。本机实际验证工具为 Go 1.27.1、PostgreSQL 18.6；没有声称已验证 Go 1.22／PostgreSQL 16。

开发可提供 `AUTHLAB_C_DSN`、`AUTHLAB_V_DSN`、`AUTHLAB_RUNTIME_TAG` 和 `AUTHLAB_ALLOW_SCHEMA_RESET=1`。测试还检查库／角色为 `hnuhole_c` 与 `hnuhole_v`、非超级用户、Unix socket 及匹配的 application_name。**测试会重建两个实验认证 schema。** 没有 DSN 时数据库案例明确跳过，不能据此报告 SQL 验证通过。

邮件测试只连接本机合成 SMTP；HTTP 测试用临时 CA 与本机 HTTPS 监听器，没有发送真实校园邮件或连接生产服务。

## 接入方式

1. 在不同数据库依序加载各侧实验迁移；这些部分 SQL 不能直接放进生产迁移序列。
2. 从数据库以外加载不同用途的密钥、版本与环境受信签名钥。`NewEligibility` 拒绝不同用途复用同一钥；HTTP 网络限流钥另行生成，V/C 安装 ID、请求 ID 和幂等键独立。
3. C的可选Passkey还须通过 `community.WithWebAuthn(WebAuthnConfig{RPID, Origins})` 注入经审阅的固定HTTPS策略；未注入时拒绝Passkey操作，不能从请求选择RP／origin。测试RP只是合成材料。为 V 注入 `SMTPProvider`／邮件服务、提交后 `Signer` 和固定 C `PeerClient`。为 C 注入 `NewPasswordPreparer` 的本地常见／泄漏密码名单及明确并发上限；`NewCommunityWithReceiptSigner` 可推动已提交收据，并在 ACK 后只读重签。
4. `NewVerifierEndpoints`／`NewCommunityEndpoints` 返回 `.Public` 和 `.Internal`，分别挂在公共 HTTPS 与内部 mTLS 监听器；内部使用 `InternalTLSConfig`，URI 身份为 `spiffe://hnuhole/<environment>/<community|verifier>`，还必须正常验证服务器域名与证书链。
5. 周期性、有界调用 `ResumePendingConfirmations`、`CleanupConfirmations`、`CleanupOTP`、C 的 `CleanupSessionResults`、`CleanupOldSessions`、`CleanupRecentDevices`、`CleanupRecoveryState`、`CleanupCredentialState`、`FinalizeDueClosures` 和 `CleanupClosureStatuses`，并对 C 未确认 outbox 执行签名与 `DeliverReceipt(..., peer.ReceiveReceipt)`。GET 查询不能代替这些 worker。正式监听器还须设置读取／头／空闲超时及容量。

普通 SMTP 没有可靠幂等或“连接断开后一定未投递”的证明。`DISPATCHING/UNKNOWN` 的原发送不会自动再次调用服务商；未决状态保留并阻止并行新发送，邮件原文在过期后清除。生产前还须提供服务商核对或受控人工处置路径，否则可能长期阻断该地址发码；这项可用性边界是明确保留的。

## 尚未完成

移动端安全存储／持久核对／登出待办与用户走查、设备通知、业务数据清理投影和生产路由／迁移仍未完成。Passkey已有隔离密码复验及WebAuthn验证；真实移动平台可发现恢复、域名／原生桥接和同步隐私走查仍待做。处罚授权联动已有受信内部命令，正式审核后台与权限仍待接入。网络限流是单进程有界预算，生产仍需多副本共享预算、反滥用与 KDF 参数／阻止名单覆盖校准。

真实独立授时、生产外部锚点与灾备演练、运营权限分离、密钥托管／轮换、日志／WAL／备份清理和真实 V/C 运营分权仍是上线门槛。隔离测试执行了原时钟回退向量；SQL 单调约束本身仍不能抵抗整库旧快照恢复，须依靠库外锚点。本机两个角色不等于两家独立运营方，内部 AI 复核不等于人类第三方审计。
