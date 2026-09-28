# Hnuhole 认证持久状态与 V/C API 契约 v1

日期：2026-09-28。状态：**实施前逻辑数据与 HTTP 契约；V/C OpenAPI 与迁移设计已成稿，未建表、未实现、未经过独立安全审计。** 本文落实[注册／释放协议](auth-privacy-registration-protocol.md)和[独立恢复策略](auth-privacy-recovery-decision.md)。精确 HTTP schema 分别由 [V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)和 [C OpenAPI](../../packages/openapi/community-auth-api.yaml)维护，物理约束和迁移顺序见[数据库迁移设计](auth-privacy-database-migration-design.md)。现有 `channel-api.yaml` 仅维护通道目录。以上均是实施前评审输入。

## 1. 部署、编码和作用域

V 与 C 是真实独立主体，使用不同 API 主机、部署权限、密钥、数据库、备份、请求编号与幂等键。测试／预发布／生产**各用互不复用的 V 与 C 签名钥**，每个 `key_epoch` 在受信配置中只绑定一个环境和预期对端；本协议固定签名消息没有环境字段，不能靠消息本身隔离环境。客户端只连接内置受信的 V、C 端点，不能由 V 的响应指定 C 地址。C 的认证库与社区业务库可做**同一 PostgreSQL 集群中的不同 schema／数据库角色**；账号状态、有效封禁、槽位、会话和释放 outbox 的权威行必须处于**同一 ACID 事务边界**。若改为两个不能共事务的物理库，须先重新设计一致性证明，不能沿用“原子关闭”承诺。公开内容注销占位是后续可重试投影，不能决定资格释放。

HTTP JSON 默认 UTF-8，拒绝未知字段、重复键、错误类型、`null`、未知查询参数和超限请求体。密码学字节用无填充 base64url，严格解码并重新编码核对规范形式：16／32／64 字节分别为 22／43／86 字符。两方安装 ID 各自随机 16 字节，幂等键各自随机 32 字节；V 通过 `V-Installation-ID` 头接收本方标识，C 在注册／登录体接收本方标识，**绝不共用**。固定完整票据必须作为单一字节字符串传递：`REGISTER/V2` 156 字节／208 字符，`RETIRE-AUTH/V1` 123／164，`RETIRED/V1` 119／159，`RELEASED/V1` 120／160。不把票据拆成可选 JSON 字段或按 JSON 顺序签名，内容仍以[注册协议第 2 节](auth-privacy-registration-protocol.md)为准。PoP 仅传 64 字节签名，153 字节正文由保存的意图重建。全部 Ed25519 验签遵循该协议第 2.1 节的项目接受配置，bootstrap 与 V/C 公钥、R 点均须规范、非单位元且处于主素数阶子群；验签成功仍须检查用途、环境、钥状态与槽位终态。输入与内部复验范围见[固定向量](auth-privacy-protocol-vectors.md)。

所有认证响应含 `Cache-Control: no-store` 和本方独立生成的 `X-Request-ID`；客户端／对端的 `X-Request-ID`、`traceparent` 等不得跨方转发。邮箱、OTP、密码、恢复码、完整资格、持钥证明、能力头和会话令牌不进入普通日志或遥测。错误沿用 `{ "error": { "code": "…", "message": "…", "details": … }, "requestId": "…" }`，可选 `details` 仅含安全的重试秒数，不能带邮箱、槽位、账号归属或密钥材料。

V/C 的 OTP、`REGISTER/V2`、意图、会话及注销截止均在相应权威库的**最终锁内裁决点**取实际 UTC 时间，不使用请求发起时刻或事务开始时刻。PostgreSQL 须在取得相关锁后用 `clock_timestamp()` 现场取样；`now()`、`CURRENT_TIMESTAMP` 和 `statement_timestamp()` 可早于锁等待结束，不能用于安全截止。裁决点与状态转换连续执行，后续不再做外部阻塞工作。时钟回退或独立授时失效时冻结依赖时间的认证操作，以受保护且不随备份回退的时间高水位校验后再恢复。[PostgreSQL 时间函数说明](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT)

私有登录用户名仅在 C 使用：6–24 个 ASCII 小写字母、数字或下划线，首字符为字母；客户端可把 ASCII 大写转小写后提交，C 以规范小写值做唯一键，不用邮箱或六位平台编号作用户名。用户名不公开展示。正式关闭时清除旧号用户名和密码验证值，允许之后被新账号选用；它**不是永久身份标识**，用户再注册若复用旧用户名可能让 C 从残余日志推断关联，界面推荐新用户名。活动账号和七天缓冲中的用户名仍唯一；用户名冲突仅在已验证注册持钥证明后返回，不能提供公开可用性查询。完全恶意的 V 能自签新资格并持对应私钥尝试候选用户名，故此限制只能降低普通未验证枚举，**不能保证 V 无法枚举用户名是否被占用**；V 仍不会因此自动得知该用户名对应哪个邮箱。

## 2. V 的逻辑持久状态

| 记录 | 关键字段／约束 | 生命周期 |
| --- | --- | --- |
| `email_quota` | 严格校验后的**精确邮箱字节**唯一键；`current_slot` 全局唯一；`pk_boot`、当前资格、版本。不得折叠大小写、别名或去掉空格 | 只保存当前 `RESERVED`；C 已提交的退役／释放收据与当前槽位相同才原子删除 |
| `used_slots` | `slot_id` 永久唯一，状态 `RESERVED/RETIRED/RELEASED`，不保存邮箱；同槽位仅允许当前原地址／原公钥在**重新验证 OTP 后**签当前窗口资格，已退役或释放的槽位永不再签给任何地址 | 注册票据有界，但当前占用与历史不复用标记仍须长期保留，不能按票据窗口清除 |
| `otp_email_state`／`otp_flows`／码版本与预算 | 按精确邮箱维护**跨 flow／设备的全局最新代次**、滚动发送预算和等待；流程保存随机 `flow_id`、六位数字码的域分离 HMAC、五分钟到期和当前码跨设备总失败数；设备＋精确邮箱连续错误跨 flow／重发保留。`K_otp` 与库／备份和其他钥分离 | 仅最新代次可成功；每当前码跨设备最多十次真错，设备三错锁五分钟；旧码有界验证值只为免计连续错，仍占请求预算。原邮件材料只短期加密存投递 outbox，投递／过期即擦除；不复制到 C |
| `confirmation_sign_jobs` | OTP 消费与 quota 保留事务中固定 REG_MSG、原确认键和准入桶；提交后才调用 HSM，签名结果持久后才响应 | 签名延迟不改变原 OTP 准入桶；待签 `CONFIRMATION_PENDING`，到期重新收码同槽位换签，不能用后台签名延长资格 |
| `retire_pending` | 按旧 `slot_id` 唯一，关联当前配额行及其版本、固定退役授权、发起时的 OTP 流程与新槽位材料、重试状态；不向 C 发送邮箱 | **调用 C 前持久写入**；存续期间拒绝原槽位续票及新槽位签发。收到 C 同槽位已提交 `RETIRED` 或 `RELEASED` 收据后原子终结；明确不可退役且尚无释放收据则保留旧配额、不签新槽位 |
| `v_idempotency` | 按 V 本地随机键唯一，含操作与**服务器密钥 HMAC** 的请求绑定值、状态、必要的短期原响应 | 发码和确认各自隔离；退役待办关联的确认键保留至终态，资格原响应最多在十分钟窗口内重取，不延长 OTP 有效期 |
| `processed_receipts` | 同槽位仅一种合法终态用途，无邮箱；保存 C 已签收据的持久处理结果 | 同用途重复只返既有结果，不清新槽位；同槽位用途冲突、未知映射或配额版本不符则核对，不能盲目 ACK |

V 校验 OTP、消耗当次确认、占用精确邮箱、检查 `used_slots` 全局唯一、固定签名消息／准入桶和登记幂等结果须在一个事务中完成；HSM 在提交后签名，签名持久后才返回资格，不能把外部签名视为 SQL 的原子部分。不同邮箱试图使用同一槽位必须失败；当前邮箱沿用原槽位时只可沿用同一公钥，且不能存在该槽位的退役待办。换新槽位前，V 先在本方事务中写 `retire_pending`，阻止旧槽位续票，再向 C 发送退役授权；C 若已提交 `RETIRED` 但拉取回包丢失且 V 尚未处理推送，V 凭同一待办重试取得同一收据，不能重新签旧槽位。V 对拉取／推送收据共用同一命令，验明原待办、旧槽位及配额版本后原子退役、登记收据并终结待办。保留原确认的受限续办关联；后续另取地址锁核对仍有效的已验证新 OTP 与固定新槽位／公钥，再保留原新槽位并建立待签任务，准入桶仍为原 OTP 验证时的桶。若 OTP 此时已过期，可先安全释放旧占用，但必须再次收码才签新资格。C 明确拒绝 `ACTIVE/CLOSED` 且 V 尚无同槽位 `RELEASED` 收据时，V 终结本次待办、保留原配额且不签新资格；之后的旧槽位续票也不能暗示可重新开户。若正式关闭的 `RELEASED` 收据与退役待办竞速，V 持久处理与当前槽位相符的释放收据、终结待办；同槽位不可能合法同时产生 RETIRED 与 RELEASED，用途冲突须事故核对而不 ACK。迟到的不可退役响应不得恢复配额或撤销已处理释放。C `RELEASED` 收据同理：先在 V 持久提交当前槽位的释放与处理结果，再向 C 确认 ACK；HTTP 已收到或签名有效本身不是 ACK。

V 还须按精确邮箱跨 `flow_id` 计数并限制滚动窗口内发码与验证请求；设备级“三错锁五分钟”是额外产品规则，不能成为唯一的在线穷举屏障。旧码识别不计入设备连续三错，但所有校验请求仍占受限请求预算；重发新码不清除邮箱级预算。阈值须经容量和误伤测试定稿，上线前不得去掉每码跨设备硬上限。

## 3. C 的逻辑持久状态

| 记录 | 关键字段／约束 | 生命周期 |
| --- | --- | --- |
| `account_auth` | 随机内部 `account_id`；当前用户名唯一、Argon2id 盐／参数／验证值、统一凭据版本、单调重设意图代次及唯一活动意图 ID；`ACTIVE/PENDING_CLOSE/CLOSED`、版本、权威封禁状态 | 正式关闭清用户名与密码验证值，保留内容所需的无邮箱内部账号及终态 |
| `slot_ledger` | `slot_id` 主键；`ACTIVE(account_id)`、`RETIRED`、`CLOSED`；活动 `account_id` 唯一 | `RETIRED/CLOSED` 不回退；关闭事务即可清除直接 `slot_id→account_id`，保留脱钩终态拒旧票 |
| `signup_intents` | 随机 32 字节意图 ID 和挑战；不可修改的 `REGISTER/V2` 资格及准入窗口、用户名、密码验证值、恢复码摘要、C 专用安装 ID；最多十分钟、状态／尝试计数 | 创建不占槽位；创建与最终提交都校验准入窗口；丢码新建意图；资格过期则废弃意图／恢复码并重新收码同槽位换签；已处理挑战不得再用 |
| `recovery_codes`／`passkeys` | 每活动账号当前一份 128 位恢复码摘要，摘要全局唯一；可选 WebAuthn 凭据 ID 全局唯一、公钥、随机用户句柄、UV／计数元数据 | 原码不落库；密码重设时旧码与**全部旧 Passkey**一起废止，凭据版本递增；关闭时废止；原码能在 C 内定位账号 |
| `reset_intents` | 受限意图、在账号锁内再次确认的当前凭据版本与重设意图代次、新恢复码摘要、十分钟到期、尝试计数、活动／废弃／已消费状态 | 新意图创建须在账号锁下复核所证明的旧码或 Passkey **仍是当前凭据且版本未变**，再废弃旧意图、递增代次并成为唯一活动意图；旧证明不得套用新版本。最终提交按凭据版本＋活动 ID／代次双重裁决。废弃／过期不消耗旧码，成功事务烧掉旧码、全部旧 Passkey 并撤销会话 |
| `sessions` | 仅存 32 字节随机令牌的摘要、独立撤销秘密的摘要、账号、C 专用安装 ID、签发时会话代次、过期／撤销时间；同账号最多一个有效移动会话 | 登录／注册建新会话时原子递增会话代次并撤销旧会话；认证与业务写均复查会话代次／撤销及账号终态／封禁；撤销摘要保留至该令牌过期后的有界重试期 |
| `closure_requests` | 客户端预生成 `closure_id` 与 256 位 `status_secret` 的摘要、账号／申请版本、由 C 数据库时间确定的 `due_at`；正式关闭后改为仅含槽位与受限状态访问；`closure_id` 唯一且绑定不可修改的原申请 | 请求提交时撤销会话；到期但关闭事务尚未提交时为 `FINALIZING`，不得再认证／恢复／写入；取消／封禁后仅保留最多三十天的只读 `CANCELLED` 状态，无账号或封禁原因；释放完成后最多三十天清理状态秘密与记录 |
| `receipt_outbox` | `(slot_id, purpose)` 唯一，提交后才签名；只含槽位、用途、签名版本、投递／ACK 状态，不含邮箱或账号 ID | `RETIRED/RELEASED` 可重签同一已提交终态；分别向退役收据／正式释放内部入口投递。C 将受信 V 的持久 ACK 与永久槽位终态的单调 `receipt_acknowledged` 同事务提交后，才按受控短期清理投递材料；重复 ACK 不重置起点，迟到回调不复活任务 |
| `c_idempotency`／`security_events` | 本方请求键、密钥 HMAC 请求绑定值、非秘密结果；受限事件不含邮箱、原密码／码、完整资格或令牌；不得长期保留账号 ID、`closure_id` 与槽位的可连接副本 | 重设提交的无秘密结果至少保留七天供缓冲期安全核对，随后按有界期限清理；其他记录只为故障核对与必要安全运营短期保存，不进入社区业务事件流。上线前须确定并验证关联记录、日志、WAL 与备份的上限，独立终态证据不得保留账号—槽位连接 |

现有 `0001_sessions.sql` 只有演示切片会话表，既无账号权威状态，也无单设备唯一性和注销事务边界；当前 `SessionValidator` 只查令牌本身，不能直接给新受保护业务路由复用为完整终态／封禁授权。现有 `requestID` 中间件还接受客户端给的 `X-Request-ID`，新 V/C 认证链必须改为**各方服务端生成且互不共用**，不得信任客户端或对端提供的关联 ID；这两处都是实现门槛，本轮不改生产代码。将来迁移须复核开发夹具与历史会话，不能让夹具成为生产认证旁路。密码与恢复码摘要的输入不能再保存一个**未加密钥的快速“请求哈希”**到幂等表；否则弱密码会多出离线猜测材料，幂等绑定统一使用与库分离的服务器 HMAC 密钥。

开户事务以唯一 `slot_id` 在 `ABSENT→ACTIVE` 与退役事务的 `ABSENT→RETIRED` 竞争，先持久提交者胜；同时创建账号、恢复凭据、一个移动会话并消费意图／挑战。用户名冲突处理意图但不占槽位。正式注销事务在同一权威库核对账号版本、有效封禁、主动登录取消时序及数据库 `due_at`，再把账号和槽位置终态、撤销所有会话、递增会话代次、写唯一释放 outbox；签名和向 V 投递只在事务提交后。

`PENDING_CLOSE` 的登录、恢复、封禁取消及新业务写入均在持账号锁的最终状态转换时比较**取锁后的实际数据库时间**；PostgreSQL 用 `clock_timestamp()` 现场取样，不能用锁等待前的应用时间、事务起始的 `now()`／`CURRENT_TIMESTAMP` 或语句起始时间。最终锁内判定与状态变更是截止竞态的裁决点，判定后不得再执行会阻塞截止裁决的外部操作；一旦该时点到达 `due_at`，即使关闭 worker 延迟也不得再取消申请或获得旧号访问，关闭提交前状态为 `FINALIZING`。

创建替代重设意图时，在账号锁内重核初步证明所见的统一凭据版本及旧恢复码摘要／Passkey 凭据仍有效，版本或凭据已变就拒绝，不能把旧证明绑定到新版本；再原子废弃旧意图、递增代次。最终密码重设同时校验统一凭据版本与唯一活动意图 ID／代次，更换密码验证值和恢复码、撤销**全部旧 Passkey 与会话**、递增凭据及会话代次并消费重设意图；并发凭据管理只能有一方提交，正式 `CLOSED` 不可重设。

每个受保护读取都须验证当前会话未撤销、代次匹配及账号终态；每个新业务写入还须在**同一权威事务的最终授权点**复查这些条件与封禁，并同会话接替、重设及关闭事务串行化：写入先提交则属于撤销前，撤销先提交则写入拒绝。仅凭请求开头的令牌校验或旧令牌离线缓存不能在撤销后继续写入。

后台发布任务的“服务端已接受”指**客户端请求在事务内完成会话、账号、封禁和身份检查，并持久提交了绑定账号／身份／不可修改内容的任务**；固定图片顺序、大小和内容散列清单，后续上传权限仅允许补齐该任务清单中的原定字节，公开前逐项核对。此后退出、换机接替或密码重设只撤销后续客户端请求权，不倒销该次已授权的任务；worker 只凭已提交任务继续处理，不拿旧 Bearer 再认证。每次真正公开入库时须与账号状态和处罚状态的变更串行化，在取锁后的最终裁决点复查未申请注销、未到期关闭且当前未被禁言／封禁；申请注销或处罚先赢则尚未公开任务取消或转失败，不能等七天到期后再阻断。公开先赢则属于申请或处罚之前，已公开内容按既定注销占位和治理规则处理。失败重试或修改内容是**新客户端请求**，须重新认证与授权。

旧备份恢复必须先冻结 V 的发码确认、注册、退役、释放，以及 C 的**全部认证、凭据恢复、会话校验、受保护读取和业务写入**；不能只冻结新会话创建而继续接受快照里的旧令牌。对照**独立且不可随同回滚的已提交事件／WAL、对端持久结果、单调前进的受信密钥／撤销版本与可信 UTC 时间高水位**重建账号关闭、槽位终态、密码／恢复凭据版本、会话撤销、释放状态和两方签名钥信任列表；独立授时源未校准或时钟倒退时不得恢复 `REGISTER/V2` 验票，避免过期票重新变有效。恢复期间拒绝所有旧会话，核对完成后仍撤销快照中的全部会话，要求用户重新登录。旧配置快照不得重新启用已撤销的 V 注册钥或 C 收据钥。若 V、C 及其提交证据同时回滚，就无法证明旧槽位、凭据与密钥撤销状态，必须继续冻结并进行事故处理，不能凭旧快照猜测开放配额或允许旧密码／恢复码。签名钥泄漏与旧票重放仍按[注册协议第 7 节](auth-privacy-registration-protocol.md)处理。

## 4. 面向客户端的 HTTP 契约

下表字段均为必填，除明确写 `?` 者；`flowId`、`intentId`、`closureId` 均为随机不透明 ID，不能互作账号标识。每个服务用自己生成的 `requestId`。状态码代表完整提交结果；连接断开或 `503` 是**结果未知**，遵守第 6 节核对，不能自行开放槽位。

| 归属与方法路径 | 输入 | 成功输出／副作用 |
| --- | --- | --- |
| V `POST /api/v1/eligibility/otp-requests` | `email`；V 专用安装头与申请幂等键 | `202 {flowId, retryAfterSeconds}`；合规空闲／占用邮箱同形受理，在允许时都发码。受理不证明送达；原倒计时不因重试重置 |
| V `GET /api/v1/eligibility/otp-request-result` | `Authorization: OtpRequestResult <原申请键>`；原 V 安装头 | `200` 为 ACCEPTED（原 flow／剩余等待）或持久 NOT_SENT；无记录也 `202 PENDING`。第四十秒受限核对，未知时可原字段原键重 POST 推进原操作，不另键发送；`410` 不证明未发送 |
| V `POST /api/v1/eligibility/otp-confirmations` | `flowId, otp, slotId, bootstrapPublicKey, releaseReceipt?`；V 安装头与确认幂等键 | `200 {registrationTicket}`；OTP／配额事务提交后持久签名再返回。待签或退役未知 `202 {state: CONFIRMATION_PENDING/RETIREMENT_PENDING, retryAfterSeconds}`；延迟过期 `422 REVERIFY_REQUIRED`，原键不再消费码 |
| V `GET /api/v1/eligibility/otp-confirmation-result` | `Authorization: OtpConfirmationResult <原确认键>`；`OTP-Flow-ID` 与原 V 安装头 | `200` 为 TICKET_AVAILABLE／REVERIFY_REQUIRED／持久 NOT_COMMITTED；未知／待签／待退役 `202`。不返票、密钥或账号；十分钟内原 POST 重取原有效票，过期须新 OTP 同槽位换签 |
| C `POST /api/v1/auth/registration-intents` | `registrationTicket, username, password, installationId` | `201 {intentId, challenge, expiresAt, recoveryCode}`；验 V 签名、公钥与准入桶，建十分钟不可改意图，一次性展示恢复码；不占槽位。丢响应新建意图，不重放原码 |
| C `POST /api/v1/auth/registrations` | `intentId, bootstrapSignature, recoveryCodeConfirmation`；C 专用最终提交幂等键 | 首次 `201 {accountId, sessionToken, expiresAt}`；锁内复验票／PoP／码确认。冲突不耗槽位，过期须换票新建意图；已提交重试只给无令牌结果再正常登录 |
| C `POST /api/v1/auth/sessions` | `username, password, installationId`；C 专用登录幂等键 | 首次 `201 {accountId, sessionToken, expiresAt}`；密码初验记录凭据版本，锁内复核未变再接替旧会话。仅截止前主动成功登录取消注销；已提交重试不重发令牌 |
| C `GET /api/v1/auth/session` | 当前 Bearer | `200 {accountId, expiresAt, username}`；`401` 清失效令牌，`503` 保留待核对。会话／账号状态从权威库验证 |
| C `POST /api/v1/auth/session-renewals` | 当前 Bearer，无请求体 | `200 {expiresAt}`；剩余七天内的真实用户活动可将**同一令牌**延到实际现在＋三十天；不另发 token／撤销秘密，不取消注销，不续失效／封禁／PENDING_CLOSE 会话；普通受保护请求共用此规则 |
| C `GET /api/v1/auth/devices` | 当前 Bearer | `200 {current, lastReplaced?}`；最多当前／最近替代两项，仅角色与必要时间，不返安装 ID、指纹或令牌；最近替代记录三十天是留存评审基线 |
| C `POST /api/v1/auth/session-revocations` | `Authorization: SessionRevoke <撤销秘密>`；不用 Bearer | 规范秘密对应会话原子撤销；已撤销、过期或无匹配记录均 `204`，不撤后来新会话。数据库未知 `503`；本地旧 expiresAt 不作完成证明 |
| C `POST /api/v1/auth/recovery-code-reset-intents` | `recoveryCode` | `201 {resetIntentId, expiresAt, username, newRecoveryCode}`；锁内确认原证明版本及旧码仍当前，原子废弃旧意图。原码不在意图创建时消费，丢新码可重新证明建立新意图 |
| C `POST /api/v1/auth/passkey-reset-options`、`POST /api/v1/auth/passkey-reset-intents` | 前者 `{}`；后者 `challengeId, webauthnAssertion` | 固定 RP 的五分钟可发现恢复挑战；有效 UV assertion 在锁内复验原版本及凭据，才返同形受限意图、私有用户名与新码；不建立正常会话 |
| C `POST /api/v1/auth/password-resets` | `resetIntentId, newPassword, newRecoveryCodeConfirmation`；C 提交幂等键 | `204` 按统一版本＋活动意图／代次原子换密码／码、删除全部旧 Passkey、撤全部会话；不自动登录或取消注销，随后正常登录并重新登记 Passkey |
| C `GET /api/v1/auth/password-reset-result` | `Authorization: ResetResult <原提交键>`；`Reset-Intent-ID` | `200 COMMITTED/NOT_COMMITTED` 或 `202 PENDING`；NOT_COMMITTED 只基于持久拒绝，或过期后同账号锁内确认无提交且意图未消费。无秘密，早到404不是终态；至少七天可核对，410不作提交结论 |
| C `GET /api/v1/auth/recovery-credentials` | 当前 Bearer | `200 {recoveryCodeAvailable, passkeys}`；仅当前凭据ID／必要时间／备份状态，无原码。十条 Passkey 上限是资源评审基线 |
| C `POST /api/v1/auth/recovery-code-rotations` | 当前会话＋`password` | `201 {rotationIntentId, expiresAt, newRecoveryCode}`；十分钟绑定当前会话与证明版本，一次显示新码；新建原子废弃旧轮换意图，丢响应不重放原码 |
| C `POST /api/v1/auth/recovery-code-rotations/{rotationIntentId}/confirmations` | 当前会话＋`newRecoveryCodeConfirmation`；C 提交幂等键 | `204` 锁内核对活动意图／版本／会话，确认后才替换原码、递增统一凭据版本并使旧管理／重设意图失效 |
| C `POST /api/v1/auth/passkey-options`、`POST /api/v1/auth/passkeys` | 当前会话；前者 `password`，后者 `challengeId, webauthnAttestation`＋提交幂等键 | 前者五分钟管理挑战绑定密码证明版本与当前会话，后者正式提交时复核。首版 ES256、UV／可发现凭据必需、attestation none，不把私有用户名放进 WebAuthn user.name |
| C `POST /api/v1/auth/passkey-removal-intents` | 当前会话＋`credentialId, password` | `201 {removalIntentId, expiresAt}`；五分钟限本账号、原凭据版本、当前会话和固定目标，不立即删凭据 |
| C `DELETE /api/v1/auth/passkeys/{credentialId}` | 当前会话；`Credential-Change-ID: <removalIntentId>`＋C 幂等键，无请求体 | `204` 锁内复验意图和固定目标后撤指定 Passkey，递增统一版本；保留恢复码和其他未撤 Passkey。不能泄露他人凭据归属 |
| C `POST /api/v1/account-closures` | 当前会话＋`password, closureId, statusDigest`；秘密提交前安全保存 | `202 {closureId, dueAt}`；锁内复验初验密码版本，申请与撤会话共事务。同 ID 绑定不可改、不重置七天；过期摘要锚点阻止重建旧申请 |
| C `GET /api/v1/account-closures/{closureId}` | `Authorization: ClosureStatus <status_secret>`，不用 Bearer | `200 {state, dueAt?, releaseReceipt?}`；仅 PENDING／FINALIZING／CANCELLED／CLOSED_RELEASE_PENDING／RELEASED，已签收据可转交V；不返账号或取消原因，无取消权 |

客户端仅把 V 侧 `registrationTicket` 带给 C，不带邮箱／OTP／V 本地 `flowId` 或幂等键。`bootstrapSignature` 是[固定 PoP 消息](auth-privacy-registration-protocol.md)的 Ed25519 签名；`recoveryCodeConfirmation` 仅可验证意图内已生成的码，不能在最终提交时选择另一恢复凭据。注销状态秘密由客户端**提交前**生成并存入系统安全存储，`statusDigest = SHA-256(ASCII("HNUHOLE/CLOSE-STATUS/V1") || 0x00 || status_secret[32])`；若安全存储不可用，不提交注销申请。C 只存摘要，专属状态认证头仅可从权威库强一致地查同一 `closureId` 的受限状态和已签收据，不能登录、取消注销或恢复旧号，也不能被任何社区 Bearer 认证路径接受或写入访问日志。响应丢失时保留原 `closureId/status_secret`，一次早到的 `404` 只表示**查询时尚无已提交记录**，不能证明原 POST 未来不会提交，也不能丢弃秘密或换新申请 ID；客户端在待确认状态重试原 `closureId/statusDigest` 的认证申请，若旧 Bearer 已撤销则继续用状态页核对，不静默主动登录。为重试而暂存的旧 Bearer 仍是完整社区凭据，必须只放系统安全存储并在客户端禁用其社区用途、取得确定结果后清除；不能把它称为“仅可查看状态”的秘密。原 POST 与重试由全局唯一 ID 串行化，不能生成第二个七天申请。

每条 32 字节随机会话令牌另导出 `revocationSecret = SHA-256(ASCII("HNUHOLE/SESSION-REVOKE/V1") || 0x00 || sessionToken[32])`。C 签发时仅存 `SHA-256(ASCII("HNUHOLE/REVOKE-STORAGE/V1") || 0x00 || revocationSecret[32])` 供定向撤销查找，不另回传撤销原文；客户端点击退出时，**先持久写绑定该旧令牌摘要的登出待完成标记**，再从该 Bearer 导出并安全保存撤销秘密，随后删除可访问社区的 Bearer，最后调用专属撤销接口；标记写入失败就不得显示退出成功。每次 App 启动与任何会话恢复之前必须先检查标记；若崩溃发生在两次安全存储修改之间，先核对本地 Bearer 与标记中的旧令牌摘要匹配，再补导出撤销秘密并清除该旧 Bearer，最后恢复撤销请求，绝不能把它当成可恢复的社区会话；本地转换完成后可另行登录，待办只针对旧令牌，不能清除或撤销后来登录的新令牌。即使网络失败，待办只保留单向导出、不能反推出 Bearer 的撤销秘密；服务器端会话在收到并提交撤销前仍可能被此前外泄的 Bearer 使用，界面须显示“本地已退出，服务器撤销待确认”。规范撤销秘密即使已过期、已撤销或无匹配记录也统一 204，表示该能力下没有活动会话；客户端取得此服务端确认才清待办，不能按本地旧 expiresAt 猜测过期，因为未知续期可能已延长服务端有效期。不能改用社区 Bearer 接口重试；普通日志和分析 SDK 不得记录两种秘密。

密码重设结果查询只从权威库读取同键、同意图的无秘密结果，不含账号、用户名或恢复材料；原幂等键与 `Reset-Intent-ID` 均不得记入普通日志。C 在意图过期后取账号锁，若并发 POST 已先提交则返回 `COMMITTED`；若仍未消费且同键无提交则以该锁内实际时间确认 `NOT_COMMITTED`，后到 POST 必须因意图过期被拒。不能在尚有效的意图或锁外查询中把“暂时没有幂等记录”当作未提交。终态意图为这种核对保留最小 ID、归属与状态元数据至少七天，敏感摘要在过期／废弃／关闭后清除；客户端收到确定结果才清理待办。查询超过保留期时明确提示结果不可核对，不能静默登录取消注销。

## 5. 内部 V/C 消息与错误边界

内部路径由独立监听／入口隔离，必须验证实际客户端证书、环境和预期对端，再验固定消息签名。OpenAPI 3.0.3 用 `x-mtls-required`／`x-allowed-peer` 扩展表达此门槛；`security: []` 只是无普通 HTTP 凭据方案，不代表公共匿名端点。不能以可伪造证书头或生成器默认中间件代替 mTLS。

| 调用 | 输入／前置 | 唯一可确认结果 |
| --- | --- | --- |
| V→C `POST /internal/v1/slot-retirements` | V 已持久写退役待办；固定 `RETIRE-AUTH(old_slot)`；环境绑定 mTLS | C 原子提交 RETIRED＋outbox 后才外部签名；未就绪 `202 RECEIPT_PENDING`，已签 `200 {retirementReceipt}`；原待办重试，ACTIVE/CLOSED 为 SLOT_NOT_RETIRABLE，不回账号资料 |
| C→V `POST /internal/v1/slot-releases` | C 终态提交后固定 `RELEASED(slot)`；环境绑定 mTLS | V 对当前槽位原子释放／终结待办，持久后 `200 {state: ACKNOWLEDGED}`；同用途旧收据不影响新槽位。未知映射或终态用途冲突 409 RELEASE_RECONCILIATION_REQUIRED，不 ACK |
| C→V `POST /internal/v1/slot-retirement-receipts` | C 终态与 outbox 提交后固定 `RETIRED(slot)`，请求只有 `retirementReceipt`；环境绑定 mTLS | V 核对当前旧槽位／版本与原退役待办，原子处理后 `200 {state: ACKNOWLEDGED}`；同用途已处理重复只 ACK。未知映射／原待办或异用途终态 409 RETIREMENT_RECONCILIATION_REQUIRED，不 ACK |
| V 内部退役收据处理 | 拉取或推送的 C `RETIRED(slot)`，同一验签与事务命令 | 持久清旧占用、登记无邮箱终态、终结原待办；保留原确认键的终态关联。收据处理不发新票，原确认续办另检查有效 OTP、固定新槽位／公钥与当前配额 |

退役收据固定 119 字节、159 字符规范 base64url，不修改签名帧。V 对重复收据也先验证当前受信钥与严格签名，逻辑幂等身份是 `(slot, purpose)`，不是签名全文或 `key_epoch`。拉取先完成、推送先完成、ACK 丢失和轮换重签均只处理一次旧配额；推送先完成后，迟到拉取的 `202`、拒绝或超时不得把原结果改回 `RETIREMENT_PENDING/NOT_COMMITTED`、重建待办或恢复旧占用。续办只允许同原确认键及保存的旧／新槽位、公钥；仍有效的新 OTP 已验证事实可继续，保留原验证准入桶，过期重新收码，不能再次消费旧码或清别的请求后来占用的新槽位。C 仅从受信 V 对本次投递取得 `200 ACKNOWLEDGED` 才持久标 ACKED；清理起点在该本地提交，重复 ACK 不延长，长期槽位终态与单调确认标记保留，迟到签名／投递不能重建已清任务。

C 的受限注销状态页在有界访问期内仍须满足 `RELEASED` 的收据响应；投递材料已清理时，可按永久 `CLOSED` 终态及当前受信钥重签同用途收据供只读响应，不重建已确认 outbox。HSM 不可用时返回 503，不将已 ACK 状态回退为待释放。灾备不得回退单调确认标记或从恢复时间重算已结束的留存；该标记不能替代 V 自己的配额／处理收据恢复证据。

客户端 `400` 是结构／编码错误，`422` 是本次语义或密码策略错误，`401 AUTHENTICATION_FAILED` 对不存在用户名、错误密码、无效恢复码、失效 Passkey 采用不暴露账号资料的同形错误；`422 REGISTRATION_TICKET_EXPIRED` 要求重新收码并对同槽位／公钥换签，不允许直接换新槽位或沿用旧意图。下一桶票据在 C 看来尚属未来时回 `422 REGISTRATION_TICKET_NOT_YET_VALID`，仍不建意图；仅距该桶开始不超过六十秒时给有界 `retryAfterSeconds` 并重试**原票**，更大偏差提示校时故障而不要求重新收码，也不因单张票放宽验票窗口。未来超过一桶的票直接拒绝。有效 OTP 后可返回 `409 ELIGIBILITY_RESERVED`，但不返回旧账号用户名／ID。签名待完成 `202 CONFIRMATION_PENDING`；退役结果未知 `202 RETIREMENT_PENDING`，不能签旧票或新票。原操作延迟到期 `422 REVERIFY_REQUIRED` 只要求新 OTP，不再次消费旧码；`409 USERNAME_UNAVAILABLE` 只能在有效注册 PoP 后出现，但任何拥有有效校邮资格的普通客户端也可能通过反复尝试猜测全局用户名是否被占用，故“私有用户名”仅指不公开展示，非不可枚举秘密。`409 REGISTRATION_COMMITTED_LOGIN_REQUIRED` 和 `409 SESSION_CREATED_RETRY_LOGIN` 均不含会话令牌。`409 SLOT_NOT_RETIRABLE` 只在内部 V/C 边界可见；`429 RATE_LIMITED` 带安全的 `Retry-After`，不因地址是否占用而改变申请响应；`503` 与超时均不代表事务未提交。禁言、封禁和账号关闭的授权错误不得泄露其他面具或邮箱。登录错误、验证码投递时延、恢复码查找、限流维度都须独立安全评审；统一文案不是完整不可枚举证明。

## 6. 幂等、未知结果和验收

V 发码、V 确认、C 最终注册、C 登录、C 密码重设各使用**本方独立**随机 32 字节 `Idempotency-Key`；重复键与不同请求内容必须拒绝。V 确认的原键可从 `CONFIRMATION_PENDING`／`RETIREMENT_PENDING` 转到已提交资格或“需重新收码”，重试只核对原操作，不再次消费 OTP 或重启退役；退役待办即使超过确认键的十分钟重取窗口也继续由 V 后台处理。V 已提交的原资格只在十分钟窗口内可重取；C 的注册／登录／重设已提交时只回无秘密的结果，**不重发会话令牌或新恢复码**。客户端在密码重设 POST **发送前**把原随机键和意图 ID 写入系统安全存储，重启后先用仅返回无秘密结果的 `ResetResult` 查询；确定结果后清除待核对记录。早到 `404` 仍不代表未提交，不能因此用新密码静默登录并取消缓冲期注销。生成一次性恢复码的意图创建刻意采用“响应丢失则新建意图并使旧意图过期／废弃”的规则，不能套用普通响应重放。幂等请求绑定值使用与数据库分离的服务器 HMAC 密钥，避免把密码或恢复码的快速散列变成额外离线攻击材料。外部 C→V 收据按合法单一槽位用途幂等并须持久 ACK；V 尚未持久处理时配额保持占用。V 已提交而 ACK 回包丢失时不回滚旧配额，C 保留原 outbox 重试至本地确认。

有限结果留存不能靠删除随机原键来拒绝迟到重试。两方 `request_results` 从首次受理即保留唯一 `(operation, key_digest)` 锚点：域分别为 `HNUHOLE/V-REQUEST-TOMBSTONE/V1`、`HNUHOLE/C-REQUEST-TOMBSTONE/V1`，`key_digest = SHA-256(ASCII(domain) || 0x00 || originalKey[32])`。完整结果到期时同一行原位收缩为 EXPIRED，仅长期保留操作＋摘要＋该状态，不留原键、时间、请求 HMAC、设备、流程、邮箱、槽位或账号；同方键摘要另有唯一约束防跨操作复用，锁后复核且唯一行永不出现删除空窗，原 POST 返回 `410 RESULT_EXPIRED` 而不重执行。EXPIRED查询只核对能力编码与原键摘要，不再验证已经清理的设备／flow／意图绑定，也不推断原提交结果。注销首次提交同事务建立 `HNUHOLE/C-CLOSURE-TOMBSTONE/V1` 域的 closureId 锚点，状态表有界清理后也不重建旧七天申请；状态 GET 的404仍不代表原申请未提交。额外长期标记有存储成本，受理前限流与容量监测须经评审，不能宣称所有状态都有 TTL。

| 故障或竞态 | 必须观察到的结果 |
| --- | --- |
| V 发码状态未知 | 原键核对；第四十秒的受限核对只在明确未发出时才允许新请求，不重置既有倒计时 |
| V 已保留槽位但确认响应丢失 | 十分钟内原键取同一资格；之后新 OTP，仍有私钥时同槽位续票，私钥丢失先退役 |
| 注册资格在 C 意图创建或最终开户前过期 | 不建立账号也不放开邮箱配额；用户重新收码，V 对原槽位／公钥签当前窗口资格，C 重新建挑战和恢复码 |
| V 已持久登记退役待办，C 拉取回包丢失 | V 尚未持久处理收据时待办阻止旧槽位续票和新资格，重试同一旧槽位；推送或拉取任一先处理即终结待办，迟到观察不回退。新 OTP 过期则再次收码 |
| 退役待办与正式注销释放并发 | 若 `RELEASED` 先到且当前槽位匹配，V 原子释放并终结待办；C 对退役的 `SLOT_NOT_RETIRABLE` 迟到也不能恢复旧配额或影响新槽位 |
| C 或 V 从旧备份恢复 | 先冻结全部认证、受保护读取和写入；以独立提交证据及对端结果修复账号／槽位／凭据版本，拒绝并撤销旧会话，完成核对后才恢复服务 |
| C 意图／新恢复码响应丢失 | 新建意图和新码；旧意图不能成为槽位占用或账号 |
| C 开户提交但响应丢失 | 旧票、旧证明与原键都不给旧会话；用户名密码登录，最多一个账号 |
| 登录提交但令牌响应丢失 | 原键只得无令牌结果；新键用用户名密码重新登录并原子替代不可见旧会话 |
| 恢复提交但响应丢失 | 从安全存储取原幂等键经 `ResetResult` 查询不含秘密的提交结果；`PENDING_CLOSE` 时不得把新密码登录当作静默核对，因为主动登录会取消注销。用户明确选择取消后才能登录；非缓冲期可用新密码正常登录，旧码成功提交后不可再用 |
| 注销申请响应丢失 | 预存 `closureId/status_secret` 从权威库查状态；早到 `404` 不作未提交证明，不丢秘密、不换 ID，原请求仍可能提交。保留原会话的受保护重试能力，使用相同 `closureId/statusDigest` 重试；若会话已撤销则继续查状态，不静默登录取消。到期与主动登录／新封禁按 `due_at` 和账号锁裁决 |
| V/C 双方或签名服务中断 | V 未持久处理已提交终态收据前不开放同邮箱新槽位；V 已提交但 ACK 回包丢失时 C 保留 outbox，重复投递不动新槽位。恢复旧备份先冻结与核对 |

实施验收至少覆盖并发同邮箱、全局重复槽位、双端超时、退役回包丢失、同键不同负载、用户名冲突、旧票／收据重放、HSM 签名失败、V ACK 丢失、恢复码与 Passkey 被盗／响应丢失、忘用户名、凭据版本竞态、会话接替和注销到期竞态。V/C 各自 OpenAPI 和数据库迁移设计已成稿；后续须审阅实际 SQL／约束、生成工具链、关联日志／备份清理与独立运营安排，再做跨组织集成测试、客户端恢复演练与独立安全评审；此处的设计核查**不是**生产安全批准。
