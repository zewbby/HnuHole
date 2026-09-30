# C 隔离实验迁移

`0001_authprivacy_lab.sql` 是认证数据库边界的最小可执行子集，属于 `authlab`，不进入现有 Goose 生产迁移序列，不改动 `services/api/migrations/0001_sessions.sql` 或 `0002_channels.sql`。

`0002_authorization_gate.sql` 在同一隔离库中追加持久授权门禁、恢复审计和注册／会话代次列；旧意图默认代次 0，不能凭迁移自动获得授权。门禁初始为 FROZEN，必须由受限恢复角色带签名证据显式推进代次后开放。此 SQL 不进入生产 Goose 迁移。

`0003_session_lifecycle.sql` 追加封禁权威行、会话撤销原因及每账号至多一条最近接替设备。账号插入触发器建立默认无封禁行，避免会话授权读取出现缺失限制行；限制版本单调。文件按编号在 `0001`、`0002` 后执行，也不进入生产 Goose 迁移。

## 执行边界

在单独、可丢弃的 C 实验数据库中，以一个事务执行完整 SQL。文件只含 Up SQL，没有 `BEGIN`、`COMMIT` 或 Down；是否提交由实验执行器决定。`CREATE SCHEMA c_auth` 刻意在已存在同名 schema 时失败，不能拿它重复覆盖既有账号数据。

## 与 Go 存储层的字段契约

以下 `32B/16B/64B` 均为经过长度约束的 `bytea`，不是编码字符串。

| 表 | 核心字段 |
| --- | --- |
| `accounts` | `account_id uuid`，`platform_number text`（六位数字），`state`，`username text COLLATE "C"`，`password_hash 32B`，`password_salt 16B`，`password_params_version bigint`，默认 1 的 `credential_version/session_generation` |
| `slot_ledger` | `slot_id 32B`，`state ACTIVE/RETIRED/CLOSED`，仅 ACTIVE 存在的唯一 `account_id`，`receipt_acknowledged`，由终态计算的 `receipt_purpose` |
| `signup_intents` | `intent_id/challenge/slot_id/bootstrap_public_key/recovery_digest 32B`，`ticket 156B`，`admission_window`，用户名及密码验证材料，`installation_id 16B`，`created_at/expires_at`，`state OPEN/CONSUMED/EXPIRED/ABANDONED`，`attempts` |
| `recovery_codes` | `account_id` 主键，全局唯一 `code_digest 32B`，`activation_version` |
| `sessions` | `token_digest/revoke_digest 32B`，`account_id`，`installation_id 16B`，`session_generation/authorization_generation`，`created_at/last_activity_at/expires_at/revoked_at`，撤销原因 |
| `account_restrictions` | 每账号一条，`NONE/BANNED`、可空结束时间、单调版本；本切片只读封禁权威状态，处罚写入口仍待实现 |
| `recent_device_replacement` | 每账号至多一条最近被接替安装标识与签入／替代时间；HTTP 不返回安装标识，三十天后有界清理 |
| `request_results` | `(operation,key_digest 32B)` 主键，另有 `UNIQUE(key_digest)`；LIVE 的 `request_hmac/hmac_key_version/intent_id/result_code/expires_at`，EXPIRED 全部清空这些可空列 |
| `receipt_outbox` | `slot_id` 主键，`purpose RETIRED/RELEASED`，`receipt_message`，`signing_key_epoch`，可空 `signature 64B`，`state PENDING_SIGN/READY/ACKED`，可空 `ack_at` |

OPEN 意图不可替换材料或延长期限。消费、过期或废弃时，须同一 UPDATE 清空挑战、票、槽位、公钥、准入桶、用户名、密码材料、恢复摘要和安装 ID；终态意图可删除，但有 LIVE 请求结果引用时先清理该引用。未撤销会话按账号部分唯一，创建新会话须先撤旧会话，不能依赖自然过期解除唯一约束。登录请求结果只存服务器 HMAC 绑定和无秘密结果；到期后原位收缩为永久摘要墓碑。会话摘要保留到服务端最终到期七天后，再由有界清理删除。

## 持久约束

- 槽位和幂等锚点不可删除；槽位终态不能回退，ACTIVE 的账号绑定不能换号，ACK 只能从 false 变为 true。
- 终态、用途和 outbox 由复合外键与提交时的 deferred constraint trigger 核对。未 ACK 的终态不能缺少 outbox，ledger 与 outbox 的 ACK 必须同事务提交。
- ACKED outbox 可清理；永久 ledger ACK 防止迟到工作重新插入投递材料。ACK 时间不因重复回调改变。
- ACTIVE→CLOSED 的释放事实要求原关联账号已 CLOSED 且没有未撤销会话；CLOSED 账号不能重新激活，控制版本不能回退。这只是签名事实防线，没有实现七天注销流程。
- 密码、恢复码、Bearer、OTP 和 bootstrap 私钥均没有原文列；幂等结果不保存账号或会话秘密响应。

不同事务仍必须按规范锁定 ledger、意图和 outbox，并在取得锁后用实际数据库时间复验窗口。数据库不负责 Ed25519 验签、槽位散列、恢复确认、Argon2 参数校准、认证限流、可信授时或 V ACK 来源；这些由调用层和后续验收验证。表拥有者仍能改 DDL 或禁用触发器；本实验不构成生产最小权限、备份恢复或双运营主体证明。

复合外键用于跨表约束，CHECK 只检查本行；可延迟触发器用于同一事务允许中间状态、提交时拒绝不完整效果，依据 [PostgreSQL 约束文档](https://www.postgresql.org/docs/current/ddl-constraints.html)和 [CREATE TRIGGER](https://www.postgresql.org/docs/current/sql-createtrigger.html)。
