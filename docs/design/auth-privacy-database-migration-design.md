# Hnuhole 认证数据库迁移设计 v1

日期：2026-09-28。状态：**实施前评审稿；没有创建或执行认证 SQL 迁移，没有实现认证代码。** 本文将[逻辑契约](auth-privacy-data-api-contract.md)、[固定协议](auth-privacy-registration-protocol.md)、[恢复规则](auth-privacy-recovery-decision.md)和[威胁模型](auth-privacy-threat-model.md)落实为物理表、事务、权限和迁移顺序。HTTP 形状分别由 [V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)和 [C OpenAPI](../../packages/openapi/community-auth-api.yaml)维护。独立评审、实际运营主体和部署证据仍是生产实施门槛。

## 1. 持久边界与共同类型

V 使用独立 PostgreSQL 实例及 `v_auth` schema，由验证方独立拥有数据库、备份、连接凭据与密钥。C 在另一实例使用 `c_auth` 与社区业务 schema；既有 `public.channels` 暂不移动。C 的账号状态、处罚权威、会话、槽位、意图、幂等结果、业务写入和收据 outbox 必须能在**同一连接的一次 ACID 事务**内操作。不能把它们拆到两台数据库后仍称原子关闭／撤销。

| 类型 | 物理表示与局部约束 |
| --- | --- |
| 精确邮箱 | V 的 `bytea`，存严格校验后的 UTF-8 字节；唯一性按字节比较，禁止大小写折叠、去空格或猜测别名等价。C 没有此类型或派生列 |
| 槽位、公钥、挑战、意图／流程／注销 ID、摘要 | `bytea NOT NULL`，对应 32 字节列 `CHECK(octet_length(col)=32)`；Ed25519 签名为 64 字节。摘要用途由列和域分离固定，不能混用 |
| 安装 ID | 每方各自随机生成 16 字节 `bytea`；V/C 不共用，不能作为旧号找回凭据或硬件身份 |
| 请求幂等键 | 每方独立随机 32 字节；数据库按操作＋本方域分离键摘要唯一，另设 UNIQUE(key_digest) 拒同原键跨操作复用；LIVE 行有请求 HMAC 及钥版本，永久最小锚点见逻辑契约第 6 节 |
| 内部账号 | C 随机 UUID v4；不是邮箱、槽位或平台编号。平台编号采用六位数字字符串，分配用安全随机数及唯一约束重试，避免按注册次序递增；当前格式最多一百万个不同编号，容量监测和扩容规则须在接近上限前另定 |
| 版本与时间 | 凭据／会话／意图代次用非负 `bigint`，溢出拒绝而不归零。协议 u32 用 `bigint CHECK(0 <= value AND value <= 4294967295)`。时间用 `timestamptz`，最终锁内用 `clock_timestamp()` 取实际时间 |
| 状态 | `text`＋明确 `CHECK(... IN (...))`；本首版不使用自由 JSON 存认证状态。跨行状态与时间有效性由事务命令保证，不能冒充单行 CHECK 能力 |

无原密码、恢复码、OTP、Bearer 或撤销秘密原文列。密码为 Argon2id 验证值、独立 16 字节盐及参数版本；输入归一化与参数校准按恢复规则。恢复码是 128 位随机秘密的域分离 SHA-256 摘要，适用快速摘要不意味着密码也可以快速散列。HTTP 无填充 base64url 解码后再按以上类型入库。

## 2. V 的表与约束

以下表仅供 V 使用；表名是后续 SQL 的设计输入，尚未存在。

| 表 | 列与约束 | 生命周期 |
| --- | --- | --- |
| `email_quota` | `email_exact bytea PK`；`current_slot bytea UNIQUE FK used_slots(slot_id)`、`bootstrap_public_key bytea`、`quota_version bigint` 均非空 | 只含当前占用；释放时原子删除。空闲地址不永久留一行 |
| `used_slots` | `slot_id bytea PK`；`state RESERVED/RETIRED/RELEASED`、版本非空；不存邮箱 | 当前槽位与历史标记全局不复用；终态长期保留，禁止退回 RESERVED |
| `otp_email_state` | `email_exact bytea PK`；全地址最新 `code_generation bigint`、最新 `flow_id bytea`、既有发送等待结束时间、邮箱滚动预算 | **跨 flow／设备**维护最新码与发送预算；新流程不重置预算。短期留存，不能进入 C |
| `otp_flows` | `flow_id bytea PK`；邮箱、V 安装 ID、码代次、五分钟 `expires_at`、当前码总失败数、消费／废弃状态；计数非负 | 只有该邮箱最新代次可成功；每个当前码跨设备最多十次真错误。过期／消费后清除验证码材料 |
| `otp_code_versions` | `(flow_id, code_generation) PK`；域分离 HMAC、`otp_key_version`、有效期、最新／被替代／过期状态；无原码 | 只为确认旧码失效、免计设备连续错误保存有界旧验证值；仍计请求预算，不能把任意不匹配码判旧码 |
| `device_email_limits` | `(installation_id, HMAC(K_limit,email_exact)) PK`；连续错误数、锁定结束时间、预算；K_limit 不在库内 | 设备对该地址三错锁五分钟，重发／重开不清零；锁定重试不续长，锁结束清连续数；邮箱级防批量预算另设 |
| `mail_outbox` | 本方任务 UUID PK；`flow_id＋code_generation UNIQUE`；收件地址、**短期加密**邮件材料及加密钥版本、投递状态、provider 操作标识 | 投递需原 OTP，故加密任务是明确旁路；任务提交后才发信，完成／过期即擦除可解密正文与地址副本。SMTP 超时保持未知，不记 NOT_SENT |
| `confirmation_sign_jobs` | 本方任务 UUID PK；`confirmation_key_digest UNIQUE`、固定 REG_MSG、准入桶、quota 版本、状态与签名结果；消息无账号材料 | OTP 与配额提交后才调用签名器。延迟不能改准入桶；过期须新 OTP 同槽位换签。释放后清理与旧邮箱相连的临时任务 |
| `retire_pending` | `old_slot bytea PK`；当前 quota 的地址／版本、新槽位／公钥、原确认键摘要、固定授权、状态 | 调 C **之前**持久写；待办期间禁止续旧票或签新票；直到 C 终态收据或明确不可退役才能结案 |
| `processed_receipts` | `slot_id PK`、purpose RETIRED/RELEASED、处理终态／版本；无邮箱 | 锁 used_slots 核对用途／终态，释放与登记共事务；异用途冲突不登记成功、不 ACK；同用途重复不清新占用，持久后才 ACK |
| `request_results` | `(operation,key_digest) PK`；LIVE行有请求HMAC／钥版本、设备、状态、flow引用及有界响应；终态不重执行 | 申请／确认隔离，无记录不判失败；票仅原键十分钟可重取。到期原位收缩EXPIRED，清空关联字段，仅操作／摘要／EXPIRED长期保留，不删唯一锚点 |

`mail_outbox` 的加密钥、K_otp、K_limit、幂等 HMAC 钥与数据库／备份分离；各钥用途和版本独立。不能声称“数据库完全没有可解密 OTP”：投递任务在完成前确实需要原码，单独数据库泄漏只能在未同时泄漏外部钥的前提下减少曝光。

V 同一精确邮箱的操作先取事务级 advisory lock。锁键用独立稳定 `K_lock` 的固定作用域 HMAC 截取 64 位；碰撞只额外排队，真正唯一性仍依精确字节 PK。轮换须暂停相关入口／worker、排空旧事务、同时切换全部调用者，不能滚动混用两把钥造成同邮箱两把锁。随后按 `email_state/quota → flow/设备预算 → used_slots → 结果/outbox` 取行锁，不存在 quota 行也须地址锁。只收到 slot 的释放入口先只读定位邮箱，再取地址锁并重读 current_slot／版本；不得先持槽位锁再反取地址锁。已处理无邮箱终态只锁 used_slots 核对重复／冲突，不反查地址。所有客户端／后台命令共用规则，不在持锁事务里调用 SMTP、HSM 或对端 HTTP。[PostgreSQL 锁说明](https://www.postgresql.org/docs/current/explicit-locking.html)

## 3. C 的表与约束

| 表 | 列与约束 | 生命周期 |
| --- | --- | --- |
| `accounts` | `account_id uuid PK`、唯一六位 platform_number、state ACTIVE/PENDING_CLOSE/CLOSED、账号／凭据／会话／reset／rotation 版本和活动指针；用户名 `text COLLATE "C"`、盐／验证值／参数在 ACTIVE/PENDING_CLOSE 非空、CLOSED 为空 | 小写用户名按部分唯一索引唯一；关闭清用户名／密码／活动指针，只留内容归属所需内部账号及终态 |
| `account_restrictions` | `account_id PK FK accounts`；权威禁言／封禁状态、有限或永久结束语义、版本 | 所有生效、解除与自动过期逻辑在账号锁下更新；不能让后台处罚投影决定认证权限 |
| `slot_ledger` | `slot_id bytea PK`；state ACTIVE/RETIRED/CLOSED；`account_id uuid UNIQUE FK accounts` 仅 ACTIVE 非空，其余必须空 | 槽位散列绑定与 PoP 通过后 ABSENT→ACTIVE；退役 ABSENT→RETIRED；关闭 ACTIVE→CLOSED 同时清 account；终态长期不删 |
| `signup_intents` | `intent_id bytea PK`、32B challenge、固定 ticket／准入桶、用户名／密码验证值／恢复摘要、安装 ID、十分钟过期、状态与尝试数 | 创建不占槽位；不存原密码／原码。已处理、过期或废弃即清敏感材料；无会话原文或长期 slot→account 结果副本 |
| `recovery_codes` | account PK FK、32B code_digest UNIQUE、激活版本 | 是否当前由行存在及摘要匹配决定，普通 Passkey 变更不使原码失效。每账号一份；最终摘要冲突不消费旧凭据／槽位，重建新码意图 |
| `passkeys` | credential_id bytea PK（1–1023B）、account FK、随机 user_handle32B、公钥／COSE 算法、签名计数、备份标志、创建时间／创建版本 | 行仍存在即仍绑定；创建版本不必等于账号后来版本，普通增删／轮换码保留其他 Passkey。首版 ES256，无 attestation／校邮／用户名；十条上限是资源基线，重设删除全部旧凭据 |
| `auth_challenges` | challenge ID／nonce 32B；kind、固定 RP/origin 策略版本、账户／会话／凭据版本绑定（可发现恢复 challenge 初始无账号）、五分钟过期、消费状态 | 只存挑战，不存原 assertion 或 attestation；锁内复核凭据仍有效后消费。密码复验所得权限不能挪给新版本／新会话 |
| `reset_intents` | ID 32B PK、account FK、证明见到的凭据版本、reset 代次、新恢复摘要、十分钟过期、活动／废弃／已消费状态 | 创建在账号锁内复核原证明，原子废弃前一活动意图；最终只允许活动 ID＋版本＋代次共同匹配。结果核对期只留最小元数据 |
| `credential_change_intents` | ID32B PK、kind ROTATE_CODE/CREATE_PASSKEY/REMOVE_PASSKEY、account FK、会话／凭据版本、rotation代次或目标credential ID、挑战／新码摘要；轮换十分钟，Passkey 管理五分钟 | 字段按kind做CHECK；轮换一个活动意图，丢码新建废弃旧意图；正式提交递增账号统一版本，使旧证明／管理／重设意图失效，不误撤其他保留凭据 |
| `sessions` | token_digest 32B PK、revoke_digest 32B UNIQUE、account FK、安装 ID16B、会话代次、创建／最近活动／有效期／撤销时间 | `UNIQUE(account_id) WHERE revoked_at IS NULL` 限一条未撤销行；新会话先撤旧再插入。过期行虽无效仍先撤再建，不在索引条件用 now() |
| `recent_device_replacement` | account PK FK；最近被接替安装 ID、登录／接替时间 | 仅设备页有限历史，不存硬件指纹；最多最近一条，三十天评审基线清理 |
| `closure_requests` | closure ID32B PK、status_digest32B、account FK（仅未正式关闭时）、申请版本／due_at、state、终态 slot（仅关闭后）、必要签收状态 | 同 ID 不能重置期限或替换摘要；每账号至多一条 PENDING，FINALIZING 是过时未关闭的派生显示。取消立即清 account／slot，正式关闭清 account；CANCELLED及释放完成后三十天清状态访问；CLOSED_RELEASE_PENDING不按TTL删除 |
| `receipt_outbox` | `slot_id PK FK slot_ledger`、purpose、固定消息、签名钥版本／签名、待签／投递／ACK状态 | 无邮箱／账号；受控命令限定 ledger RETIRED→RETIRED、CLOSED→RELEASED，禁止同槽位异用途。只签已提交终态，待签202 RECEIPT_PENDING，无可释放收据；持久 ACK 前保留 |
| `request_results` | `(operation,key_digest) PK`；LIVE行有请求HMAC／钥版本、意图引用、无秘密结果、保留结束时间；EXPIRED仅操作／摘要／状态 | 与业务提交共事务，注册／登录不重放令牌。到期原位清空关联字段而不删锚点；注销首次提交共事务建CLOSURE＋closureId独立域摘要锚点，状态表删后原ID也不能再申请 |
| `security_events` | 本方事件 ID、受限账户／动作／版本、最小时间；无邮箱、槽位、凭据原文、完整票据 | 用于恢复提醒和事故核对，和普通运营日志隔离；不进入社区公开流，也不向 V 发送恢复事件 |

`accounts.active_reset_intent_id/active_rotation_intent_id` 引用意图的 `(account_id,intent_id)` 复合唯一键，采用 `DEFERRABLE INITIALLY DEFERRED` 复合外键，防止指向别人的意图；意图 account FK 保证账号存在。活动状态 `(account_id)` 部分唯一索引再限一份活动意图。状态、版本与指针共事务，过期先废弃旧行；统一版本用于锁前证明／挑战的快照 CAS，不要求所有保留凭据的创建版本相等。PostgreSQL 的 CHECK 只处理本行，跨表归属和终态关系由受控命令／必要触发器复核，不能用读取其他表的 CHECK 函数假装永久约束。[约束说明](https://www.postgresql.org/docs/current/ddl-constraints.html)、[部分索引](https://www.postgresql.org/docs/current/indexes-partial.html)

## 4. 事务命令与固定锁顺序

### 4.1 C 的锁顺序

涉及已有账号时，先通过摘要或意图 ID **只读定位**账号，再依次取得 `accounts → restrictions → slot（若需要）→ 意图/挑战 → 恢复码/Passkey → sessions → request_results/outbox` 的锁；最终重复验证定位材料仍属于该账号、凭据版本／会话代次仍匹配。需要多个同类行时按主键字节排序，所有入口、worker、处罚和结果核对共用顺序。

未开户注册与槽位退役先取固定域槽位散列导出的事务级 advisory lock，再取已有 slot 行；ABSENT 也锁。它们**不取得任何已有账号锁**：ACTIVE/CLOSED 立即拒绝退役／重复注册；注册只创建新随机账号。关闭命令取得已有账号锁后再取本账号槽位锁；此限定避免“持槽位锁再等旧账号锁”形成反向死锁。主键唯一约束仍是最后裁决，不能把 advisory lock 当唯一约束替代。

各幂等操作在任何不可逆副作用前取得／认领本操作键的唯一锚点，同键竞争锁后复核 LIVE／EXPIRED；认领、业务结果与状态更新共事务，清理只锁并原位收缩该行，不另取账号锁。不同负载同键拒绝；EXPIRED 从不再次执行。首次无有效授权的批量请求不能无控创建永久锚点，受理预算和容量门槛须校准。

所有安全时间检查在所需锁全部取得后取 `clock_timestamp()`，检查／状态变更连续执行，然后提交；不使用事务开始时间，不在最终裁决后做外部签名／投递。密码 KDF、WebAuthn 验签等可先在受限并发工作区计算，但取得账号锁后必须重核原版本和当前验证材料；先验成功不能给新版本签发权限。

### 4.2 必须同事务提交的命令

| 命令 | 原子效果与最终检查 |
| --- | --- |
| V 发码受理 | 地址／设备预算及已有等待检查、全邮箱码代次更新、新 flow／加密邮件 outbox／幂等受理结果共事务。投递任务用同一 provider 幂等身份；无可靠去重的 SMTP 不自动重发结果未知任务 |
| V OTP 确认 | 最新码／五分钟／三错与十错预算核验、OTP 消费、当前槽位唯一保留、固定准入桶和签名任务／原确认结果共事务；HSM 在提交后签，响应未就绪为 CONFIRMATION_PENDING |
| V 退役／释放核对 | 先只读按槽位定位地址，再持地址锁重查并比较当前 slot＋quota版本，处理收据、清当前 quota、终结同槽位待办共事务；持久后 ACK。新槽位还需当前有效的新 OTP；不能只靠旧签名任务自动新签 |
| C 开户／退役 | 在槽位锁下用唯一 slot 裁定 ABSENT→ACTIVE/RETIRED；开户同时验限时票、严格公钥、PoP、不可改意图和码确认，创建账号／当前恢复码／唯一会话／无秘密请求结果；退役只写终态与待签收据 |
| C 主动登录 | 锁内复核密码验证时的凭据版本、账号／封禁与真实截止；仅截止前主动成功登录取消注销；递增会话代次、撤旧、建新、设备替代记录及无令牌重试结果共事务 |
| C 静默续期 | 只限仍有效、未撤销且代次匹配的同一会话；剩余不超过七天的真实登录后活动可将有效期延到本次实际时间＋三十天。保持原 token/revoke 摘要，不增会话代次，不取消注销；不能续 PENDING_CLOSE/CLOSED 或封禁会话 |
| C 定向退出 | 先由 revoke 摘要定位账号再取锁复查；只撤匹配会话，当前会话撤销使相关管理意图失效，旧替代会话待办不影响后来会话。规范秘密无匹配记录也 204，表示该能力下没有活动会话 |
| C 建恢复意图 | 锁内复核初步证明所见版本及旧码／Passkey仍当前，重核账号截止；废弃旧意图、递增reset代次并建唯一新活动意图。恢复码原文只进首次响应，不存入幂等响应 |
| C 最终重设 | 活动 ID＋凭据版本＋reset代次＋实际有效期＋新码确认共同匹配；更换密码／恢复码、删除所有旧 Passkey、递增凭据／会话代次、撤所有会话、消费意图／记录无秘密结果共事务；不自动登录，不取消注销 |
| C 重设结果查询 | 同键同意图的持久结果可直接读取；没有结果时在意图过期后取同一账号锁，未消费且仍无提交才确认 NOT_COMMITTED，后来 POST 必须因过期被拒；尚有效或未知记录只返回 PENDING |
| C 凭据管理 | 原意图绑定的当前会话、原密码证明版本及目标再次匹配；轮换原码／增删 Passkey与凭据版本递增共事务。仅更新签名计数／备份标志不属于控制凭据变更，不递增控制版本 |
| C 申请注销 | 当前会话＋新鲜密码原版本＋可注销处罚状态、唯一closureId及不可改status摘要；进入PENDING_CLOSE、撤会话、建立截止和状态记录共事务。worker公开入库遇PENDING_CLOSE即停止未公开任务 |
| C 最终关闭 | 同账号锁下真实时间到期且申请版本未取消；账号CLOSED、清密码／用户名／恢复路径及全部活动指针、槽位CLOSED并清其account、撤会话、状态访问清account、释放outbox共事务。外部签名／投递只能读已提交outbox |
| C 新业务写入／公开 | 与账号关闭、会话接替、恢复、处罚共账号锁，最终授权同事务；已受理任务固定内容与图片清单，公开前另核当前注销／处罚。权限已撤后的新客户端修改不能冒充原任务 |

一期采用 `READ COMMITTED`＋上述锁与唯一约束；每次取得锁后重新读权威行，不沿用锁前快照。若后续改 `SERIALIZABLE`，须把整个事务作为单位处理 serialization failure；无论哪种隔离等级，提交后出站任务的事实不能随请求重试被撤销。锁等待／语句／事务超时须有上线定值，超时对客户端仍是结果未知。

## 5. 权限、终态证据与清理

V/C 各有不用于请求的迁移 owner；运行角色无 DDL、无修改角色／授信钥权限。V 运行角色只访问 V 表。C 受信的认证命令连接可在同事务访问必要认证和业务行，普通社区读角色、审核后台与导出角色没有 `c_auth` 槽位、验证值或恢复表权限；业务写入不能绕过最终认证命令。此分权不保证对被完全攻陷的 C 运行进程匿名，仍按威胁模型陈述。

以下是迁移设计的**有界留存评审基线**，须落实为清理任务、备份策略和验证证据才能用于隐私承诺：

- OTP 原邮件材料发送／过期即擦除；OTP流程及设备／邮箱短期风控最多二十四小时，已确认资格原响应仅十分钟可取。待退役、待释放事件保留到双方终态核对，结案后清除邮箱关联副本；不能因清理 TTL 放配额。
- C 意图秘密处理完或过期即清；无秘密重设结果与最小意图核对元数据至少七天、评审基线七天清理；其他最终命令完整结果也采用七天；永久原位 EXPIRED 锚点只留操作／域摘要／状态，无原键或关联材料，拒迟到原POST。注销状态清理不删申请ID域摘要锚点；这些长期标记须单独计入容量，不能宣称全部认证状态都有TTL。
- 最近替代设备三十天；取消的注销状态三十天，释放完成后三十天状态权限清理。会话／撤销摘要保留至其**服务端最终有效期**后七天；不能按客户端旧 expiresAt 清待办，因为未知续期可能已延长。
- 普通日志不记录认证正文或秘密，诊断关联元数据评审基线最多七天；数据库 WAL 及加密备份分别按七天／十四天的评审基线清理。实际恢复目标或运营规则要求更长保留时，须先更新本设计和用户隐私说明，不暗中保留。
- C 的脱钩槽位终态与 V 无邮箱的已用槽位／处理收据长期保留；C 内部内容归属账号按既定公开内容保留规则维护。关闭不等于历史备份和用户副本立即删除。

灾备证据必须位于不可随数据库快照回退的独立权限域，维护账号控制版本／关闭事实、槽位终态、受信钥撤销版本及时间高水位；压缩后的独立终态证据不保留 account＋slot共同键、共同事件编号或可直查连接。完整近期 WAL／备份仍可能含旧映射，在上述有界窗口内须计入两库泄漏边界。

**版本证据不等于最新凭据材料。** 恢复到旧快照后，若证据表明凭据版本曾前进但最新密码验证值、恢复摘要／Passkey行无法从可信增量恢复，不能把旧版本重新启用；冻结相关账号并按事故流程核对，不通过邮箱重置。恢复期间全部认证与受保护读写冻结，校时、账号／槽位／凭据／信任策略核对完成后撤销所有快照会话再放行。

## 6. 从当前切片迁移的顺序

当前只有 [0001_sessions.sql](../../services/api/migrations/0001_sessions.sql) 的演示会话和 [0002_channels.sql](../../services/api/migrations/0002_channels.sql) 的通道。**不修改已经发布的 0001/0002，也不凭任意旧 account_id 伪造真实用户名、密码或校园资格。** 以下编号是设计计划，不是本轮可执行文件。

| 阶段 | 后续迁移与放行条件 |
| --- | --- |
| M0 盘点 | 确认各环境是否仅有开发夹具，保存可审计基线；取得独立审阅结论、真实 V/C 主体、密钥／授时／留存安排。存在真实历史用户时先另写经审阅的迁移方案，不能套用清夹具流程 |
| M1 扩展 | V 独立迁移序列建立上述 V 表；C 0003 建 accounts/restrictions/slot/新 sessions，0004 建 credentials/intents/closure/outbox/results。建立约束、索引与最小权限；新路由仍关闭，旧通道目录不动 |
| M2 验证 | 在隔离测试环境执行实际SQL并验证并发／故障矩阵，校验签名字节向量、OpenAPI生成和真实客户端；独立复测通过后再部署新的终态／封禁验证器 |
| M3 切换 | 暂停认证写入口，确保不会并行签发两套会话；演示 public.sessions 失效且运行角色撤旧表访问，客户端用新注册／登录建立会话。生产验收确认所有受保护路由只接受 c_auth 权威状态 |
| M4 收缩 | 观察与核对后单独新迁移清除遗留演示表和夹具；不建只检查 token 的兼容视图，不回退到旧 SessionValidator。channels 数据和既定内容规则不因认证迁移被重建 |

M1 未接入新流量时可撤销尚未使用的新表；**一旦消费槽位、改凭据、撤会话或关闭账号，普通 Down 迁移不可回滚这些事实**。后续应用降级也必须保留权威终态检查和已撤销记录，否则冻结服务并前向修复；不从旧备份直接开放。迁移账号表的破坏性清理、真实数据处理和正式部署应在具体操作包经审阅后执行，本轮没有执行这些动作。

## 7. 迁移验收包

实际 SQL／实现阶段须提供：全部列类型和局部 CHECK、外键／部分唯一索引、固定锁顺序、应用角色 GRANT／撤权、清理任务及备份策略；并验证至少以下交错：

1. 同邮箱不同 flow／设备重发只让最新码有效；预算不重置，邮件超时不触发第二次无控发送；V 配额提交但 HSM中断只留下同槽位待签任务。
2. 不存在槽位下注册／退役争唯一终态；开户／用户名冲突／票据到期不误耗配额；C签名服务中断或V ACK丢失不提前释放。
3. 旧恢复证明在取账号锁前被轮换、新意图替代旧意图、凭据管理与最终重设并发，只保留一套当前凭据；结果查询与迟到提交只得一种终态。
4. 登录／续期／定向退出／换机／封禁并发；旧撤销秘密不能撤新会话，过期行与活动部分索引不让双会话通过。
5. 注销提交回包丢失、锁等待越过七天、处罚／公开／关闭交错；没有迟到登录取消，未公开任务不在注销申请后公开。
6. 旧数据库与旧信任配置、时间倒退、最新凭据材料缺失；核对前旧密码／码／会话均不得因恢复而重新有效。

这份迁移设计和 OpenAPI 静态校验只是审阅输入。它们不能证明事务实现、真实移动端或双组织部署已经安全，也不代替[独立审阅门槛](auth-privacy-threat-model.md)。
