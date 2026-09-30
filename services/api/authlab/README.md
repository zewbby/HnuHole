# 认证隐私隔离实现与验证

用户已授权进入 Phase E；本隔离切片已实现第 0 步 Authorization Safety Gate，并继续加入用户名密码登录与服务端会话管理。代码在 `internal/authprivacy`、`internal/authprivacy/protocol` 与 `internal/authprivacyhttp`。本目录使用独立实验数据库与合成材料；现有 API 主路由、演示认证器和生产 Goose 迁移没有接入这套认证。

校邮与 HTTP 切片的交付见[历史报告](../../../docs/design/auth-privacy-eligibility-http-validation-report.md)；首条数据库切片见[更早报告](../../../docs/design/auth-privacy-isolated-validation-report.md)。`verification.json` 固定首轮证据，`eligibility-http-verification.json` 固定上一轮证据；第 0 步另有新记录。

第 0 步实现与门槛见[Authorization Safety Gate 交付报告](../../../docs/design/auth-authorization-safety-gate-validation-report.md)，机器记录在 `authorization-safety-gate-verification.json`。登录／会话切片见[交付报告](../../../docs/design/auth-privacy-session-lifecycle-validation-report.md)与 `session-lifecycle-verification.json`。历史验证 JSON 保持不改。

## 已实现

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
3. 为 V 注入 `SMTPProvider`／邮件服务、提交后 `Signer` 和固定 C `PeerClient`。为 C 注入 `NewPasswordPreparer` 的本地常见／泄漏密码名单及明确并发上限；`NewCommunityWithReceiptSigner` 可推动已提交收据，并在 ACK 后只读重签。
4. `NewVerifierEndpoints`／`NewCommunityEndpoints` 返回 `.Public` 和 `.Internal`，分别挂在公共 HTTPS 与内部 mTLS 监听器；内部使用 `InternalTLSConfig`，URI 身份为 `spiffe://hnuhole/<environment>/<community|verifier>`，还必须正常验证服务器域名与证书链。
5. 周期性、有界调用 `ResumePendingConfirmations`、`CleanupConfirmations`、`CleanupOTP`、C 的 `CleanupSessionResults`、`CleanupOldSessions` 和 `CleanupRecentDevices`，并对 C 未确认 outbox 执行签名与 `DeliverReceipt(..., peer.ReceiveReceipt)`。GET 查询不能代替这些 worker。正式监听器还须设置读取／头／空闲超时及容量。

普通 SMTP 没有可靠幂等或“连接断开后一定未投递”的证明。`DISPATCHING/UNKNOWN` 的原发送不会自动再次调用服务商；未决状态保留并阻止并行新发送，邮件原文在过期后清除。生产前还须提供服务商核对或受控人工处置路径，否则可能长期阻断该地址发码；这项可用性边界是明确保留的。

## 尚未完成

独立恢复服务／Passkey、七天注销、移动端安全存储／登出待办与用户走查、生产路由和迁移均未完成。由于注销截止表及处罚写入流程尚未接入，本实验对 `PENDING_CLOSE` 登录采取 fail closed，不能执行合同中的截止前主动登录取消注销；封禁状态能阻断登录／认证，但后续处罚写入仍必须在同一权威事务撤销活动会话。网络限流是单进程有界预算，生产仍需多副本共享预算、反滥用与 KDF 参数／阻止名单覆盖校准。

真实独立授时、生产外部锚点与灾备演练、运营权限分离、密钥托管／轮换、日志／WAL／备份清理和真实 V/C 运营分权仍是上线门槛。隔离测试执行了原时钟回退向量；SQL 单调约束本身仍不能抵抗整库旧快照恢复，须依靠库外锚点。本机两个角色不等于两家独立运营方，内部 AI 复核不等于人类第三方审计。
