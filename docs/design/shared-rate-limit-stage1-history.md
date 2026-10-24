# 共享限流与动作防刷：阶段 1 基线与配置草案

任务 `SHARED-RATE-LIMIT-01`；2026-10-24；基线 `origin/main@8ed8f28`；分支 `feat/shared-rate-limit-abuse-control`。本页为静态盘点与待实现契约，**新增规则尚未实现、启用或验收**。需求来源为《HnuHole 共享限流和动作级防刷需求说明书 V1.0》（2026-10-24）及本轮用户补充；原文写的 `ce140d57` 是需求历史基线，本任务从实际最新 main 开始。

## 范围与不能改变的边界

- Redis 只决定准入；会话代次、账号/身份归属、C/V Safety Gate、最终 PostgreSQL 事务、永久幂等回执与业务上限继续执行。账号来自已验证会话，所有身份共享账号额度，动作分别计数。
- 不引入 RocketMQ，沿用持久 Worker/Outbox。普通同步、拉取、ACK、查询回执与发送独立；ACK 不扣发送额度，接收持久化后才 ACK。
- 首次联系仍只允许对方回复前一条文字，图片禁发；删除/撤回不重置 `low_sent/high_sent`。`WAITING_FOR_REPLY` 属明确业务拒绝，不做定时自动重发。
- 入口每次请求均计，包括失败/重试；动作按账号、动作、有效幂等键与相同内容最多扣一次。同键异内容拒绝；获准后失败不退，准入前拒绝不扣。真实上传每次接收字节均计，不能因幂等而免流量。
- 用户行为：发帖/评论 429 自动保留草稿与原身份、帖子、回复目标、图片任务；提示“短时间内操作次数达到上限，请等待 X 秒后重试”，到期用户手动重试，不自动发布。私信立即本地显示气泡并可靠保存，服务端确认才算成功；429 使用有界本地队列，沿用原键到期自动重试，同会话保序。排队、发送、结果未知仅转圈；明确业务拒绝才失败。只能取消确定未发任务；未知在途只能停后续并核对，不能假称撤销成功。

## 实际源码地图与既有效果

下表是 `8ed8f28` 源码事实，不是线上环境观测；未读取运行中配置、数据库或设备。

| 领域 | 入口/方法（仓库相对路径） | 已有规则与不足 |
| --- | --- | --- |
| HTTP 入口 | `services/api/internal/authprivacyhttp/endpoints.go` 的 boundary 包装；`limits.go` 的 `networkLimiter.allow`、`canonicalNetwork` | 进程内 mutex/map 固定窗口；runtime 固定 60 秒，GET 查询与其余请求独立桶。容量由 `networkMutationCapacity/networkQueryCapacity/networkMaxEntries` 必填配置，阈值范围 1–10000/1–10000/1–65536；没有可据源码推定的线上数值。满 map 清过期项后仍满则拒绝。仅 RemoteAddr，IPv4 单地址、IPv6 /64；当前完全不信任转发头，因此不能伪造绕过，但反代部署会把代理汇成一人。重启清空且实例不共享。 |
| 配置/装配 | `authprivacyruntime/config.go`、`server.go` | 无 Redis 依赖/连接/模式/故障策略/可信代理设置；`services/api/go.mod` 无 Redis 客户端。 |
| 密码登录 | `authprivacyhttp/session_endpoints.go` 的 `communitySessionPublic`；`authprivacy/community_sessions.go` 的 `proveUsernamePassword/createSession` | 已有不存在用户名 dummy-password 验证及最终锁内复核；只有总入口桶，缺登录标识×来源组合短窗与连续失败规则。密码运算另有并发资源保护，不能替代共享防刷。邮箱登录经 `email_login_endpoints.go/community_email_login.go` 衔接。 |
| 验证码 | `authprivacy/eligibility_otp.go` 的 `consumeOTPBudget/RequestOTP/queueOTP/verifyOTPInTx`；`eligibility_email_login.go`；HTTP `endpoints.go/email_login_endpoints.go` | V 的 PostgreSQL 邮箱 SEND 10/1小时、VERIFY 30/10分钟（`server.go` 装配）；发送冷却 60秒、验证码有效5分钟、替换/一次性消费；安装ID×邮箱连续错3次冷却5分钟、单码错10次失效。均保留；C Redis 不得接触邮箱。新增共享入口不能破坏同状态受理及枚举保护。 |
| 发帖 | `authprivacy/community_posts.go` 的 `ExecutePostCommand/postCommandBudget/postLiveBudget`；HTTP `posts_endpoints.go` | 账号锁+最终Gate内，各类新命令回执合计120/滚动60秒（含 seal/拒绝等，不等于120次发表）；回执重放先于限额。另有128个 owner_visible 且最新尝试 ACCEPTED/FAILED 的存活任务上限；SQL保持生效。 |
| 评论 | `authprivacy/community_comments.go` 的 `ExecuteCommentCommand/commentBudget`；`community_comments_worker.go`；HTTP `comments_endpoints.go` | 各类新回执合计120/滚动60秒，同样不是专门发表频率。新增动作窗必须独立于删/赞/seal。`community_comments_read.go` 另有每账号128快照、快照5分钟；超过10000评论的快照保护仍保留。 |
| 私信文字/新会话 | `authprivacy/community_direct_messages.go` 的 `SendDMText/GetDMCommand/PullDM/AcknowledgeDM`；HTTP `direct_message_endpoints.go` | 文本首次发送在同一事务中隐式新建唯一身份对会话，没有单独创建接口；账号/会话各4096条未ACK上限。持久回执 `c_dm.commands` 按 owner_account+command_id，HMAC内容指纹排除 attempt，SENT重放、失败后 attempt+1可重试。没有时间频率上限。新会话动作必须仅对实际不存在的会话收费，不能仅看客户端 conversationId 为空。 |
| 私信图片 | `community_direct_message_images.go` 的 `SendDMImage`；HTTP `direct_message_chat_endpoints.go` | JSON/base64随发送一次传入，HTTP body上限14MiB+8192；解码图最大10MiB，组最多9图。账号/会话各4096未ACK，图片未ACK字节账号128MiB、全局1GiB。这是库存保护，不是每时窗传输预算；同一请求同时涉及发送与上传。 |
| 帖子/评论图片 | HTTP `post_images_endpoints.go/communityPostImages`、`comments_endpoints.go/communityCommentsPublic`；业务 `community_post_images.go`、`community_comments_business.go` | `io.ReadAll(io.LimitReader(..., MaxBytes+1))`，单图10MiB；帖子最多9图，评论既有单图。没有按账号上传次数/实际接收字节窗口。 |
| 头像 | HTTP `identity_avatar_endpoints.go/communityIdentityAvatar`；业务 `community_identity_avatars.go` | 原始5MiB上限，规范化结果512KiB；没有按时间共享传输预算。 |
| 读取 | `feed_endpoints.go`、`posts_endpoints.go`、`comments_endpoints.go`、DM目录/pending/controls/media/query | 只有入口GET桶和已有快照/分页大小边界；普通滚动与私信每4秒同步应作为新规则观察样本。ACK虽POST，也属于独立控制读取类保护，不是发送。 |

## HTTP、幂等回执与可恢复性契约

1. 保持稳定错误码 `RATE_LIMITED`、HTTP 429、整数 `Retry-After`、`Cache-Control: no-store`、服务端生成的 `X-Request-ID`，不得带成功续期头。真实等待取所有命中窗口最晚可准入时间，向上取整且至少1秒，不得早于真实解除时间。
2. 有两种既有错误方言：auth `boundary.fail` 允许 `error.details.retryAfterSeconds` 并带同值头；post/comment/DM `postFail` 严格只有 `error.code/message`，等待仅在头；http_post_api.dart同时严格限制等待1–300秒。不能擅自往所有错误体加 details。当前 `postFail` 把等待截到300秒；小时级预算需要统一扩展上限并同步严格客户端/契约，或只定义不超过300秒且到期重新核对的明确协议；阶段2必须锁定，不能返回虚假的剩余等待。
3. 帖子 `PostCommand` 和评论 `CommentCommand` 使用原有32字节命令键、规范 RequestDigest/HMAC指纹与持久SQL回执；DM使用原UUID命令路径。**不强加新的通用幂等键长度**。读已提交回执并校验内容冲突必须优先于动作扣费；重放仍付入口费用，不受耗尽动作额度阻止原结果查询。
4. 准入前429不写成业务REJECTED/FAILED/NOT_ACCEPTED/sealed，也不能由客户端立即seal掉原命令。原键原内容到期可重试。若已存在未知在途，新的429只说明本次被拒，不能证明旧请求没执行；查询原回执/按原键核对后再恢复草稿，禁止生成新键自动补发。
5. Redis准入成功→进程崩溃/DB失败：额度与去重仍在，不退款；原操作重试不能重复扣。SQL已提交→Redis去重过期：先SQL重放，不能重扣或重复业务。TTL不足覆盖的旧命令须有可验证时效或永久DB锚点，不能把“key不存在”视为首次操作。Redis只能保存指纹摘要，不能保存正文。
6. DM `SendDMText` 首次同时涉及 send 与 conversation.create；图片同时涉及 send、upload.attempt、upload.bytes。多项准入须原子判断后一次扣减，不能一项拒绝另一项已经扣。实际读取过的字节已经消耗，不退款，与逻辑动作前置拒绝区别处理。
7. 同键异内容，即使额度已空也应得到 `COMMAND_CONFLICT` 而非覆盖原记录；并发中的指纹绑定、计费标记与回执核对必须覆盖跨实例、崩溃与TTL到期。Redis不代替业务一次性。

## 客户端现状与必须补点

| 模块 | 可复用的实现 | 本期必须补齐 |
| --- | --- | --- |
| 发帖 | `apps/mobile/lib/src/posts/post_controller.dart` 的 `saveDraft/publish/_send/reconcile`；`apps/mobile/lib/src/storage/post_store.dart`、上传模型与媒体存储；提交前SQLite持久化、未知结果核对和账号/epoch围栏已有。`http_post_api.dart` 已解析429 Retry-After到 `PostFailure.retryAfterSeconds`。 | `_failure/_send` 目前走通用拒绝或未知结果核对，无429草稿/等待状态与手动重试门槛；为可信429保存完整原材料、显示剩余秒，防自动发表；未知原操作保持围栏。所有上传阶段429同样保留材料，不误作成功或永久失败。 |
| 评论 | `comment_controller.dart`、`comment_journal.dart`、`comment_models.dart` 持久意图与原binding，sending崩溃变unknown；`comment_http.dart` 严格错误体和回执；`comment_views.dart` 本地本人首条展示。 | `CommentHttpFailure` 当前仅status/code，丢失Retry-After；需加严格解析与统一可恢复错误映射、持久等待/草稿、图片任务、明确目标绑定及手动重试。429不能当 `CommentCommandRejected` 固化，也不能清输入/自动重发。 |
| 私信 | `dm_store.dart` 加密SQLite FULL事务在enqueue返回前完成；`dm_controller.dart` 4秒同步，work按ordinal最多100条，queued→unknown前写盘、先GET回执再PUT；收件落盘后ACK；`dm_chat_store.dart` 分块持久图片。`direct_message_bubble.dart` 未确认显示转圈，明确失败叹号，符合既有视觉。 | 目前每4秒循环不读取Retry-After，没有持久notBefore/退避/到期调度或全队列容量上限；100是批次非队列上限。需按账号/身份对会话分组阻塞前项，未知/限流前项不被后项越过，避免某会话阻塞所有ACK/其他会话；同键恢复、重启等待恢复、取消明确未发与隐藏未知只核对分开。不得定时重发WAITING_FOR_REPLY。 |
| 同步/生命周期 | DM账号store固定绑定、epoch/授权回调、detach及身份退休/注销清理已有；读取与ACK由既有同步工作承担。 | 单项GET回执或PUT发送的429均保留原id/intent；账号发送限流暂停该账号发送调度，但继续收件/ACK。单项429不能中断整轮收件/ACK；独立read/control backoff避免4秒紧重试。等待计时跨重启与时钟回拨要有界且保守，退出/切账号/删除身份需取消旧调度但保留原隔离规范。 |
| 上传 | raw图片PUT与DM JSON/body均有大小上限；既有安全存储与图片任务可以复用。 | 在读取body前鉴别可信账号并验证会话，不信任自报身份；逐块实际接收预算，含截断/取消/非法图/重传及DM base64线上的实际body字节。图片字段声明byteLength只能验证，不当作计费事实。 |

## 完整规则配置草案（阶段2可修订；不是生效配置）

统一语义：`mode=off|observe|enforce`。以下新增项初始全部 `observe`；SQL与原入口既有规则保持 `enforce`，新增off/observe不能停既有规则。观察只记录假想拒绝，不改变业务或返回429。只有A1–A6证据与正常流量观察足够后才逐项启用。限额不按4.6万潜在人数推算。

表中 SW=精确滑动窗口（server time，边界 `(now-window, now]`）；TB=令牌桶。每条key含独立部署环境、所属服务域、规则版本、动作与HMAC主体。C主体HMAC账号不含身份；IP用独立短期HMAC；登录标识按既有严格校验语义摘要。V/C分开密钥/命名空间/访问权限。

| 规则ID / 适用接口 | 主体 | 算法 / 额度 / 单位 | TTL与容量（候选） | 模式 / 故障策略 |
| --- | --- | --- | --- | --- |
| legacy.network / 所有外部HTTP | IPv4或IPv6 /64 | 固定60s；mutation/query沿启动配置（未知实际值，不填写假值） | 既有map最大65536上限，过期回收 | 既有enforce持续；迁移期不得双重收紧，可信代理改造另验 |
| legacy.post.commands / 各帖子命令含seal | 账号 | SQL精确滚动60s，120个新回执 | SQL原留存/锚点规则 | enforce，DB失败503 |
| legacy.post.live / 新建帖 | 账号 | 128个可见ACCEPTED/FAILED任务 | 原SQL生命周期 | enforce，DB失败503 |
| legacy.comment.commands / 各评论命令含seal | 账号 | SQL精确滚动60s，120个新回执 | 原SQL生命周期 | enforce，DB失败503 |
| legacy.comment.snapshots / 评论列表 | 账号 | 128个存活快照，每快照5分钟；原10000条保护 | 原SQL | enforce |
| legacy.otp.send/verify / V注册/邮箱登录验证码 | V邮箱 | SQL SEND10/小时，VERIFY30/10分钟；冷却/错误次数/一次性沿上文 | 原V清理与永久回执规则 | enforce，V Gate/DB失败503 |
| legacy.dm.pending / DM文字/图片 | 账号、会话（两个独立上限） | 各4096未ACK；图片账号128MiB、全局1GiB未ACK | 既有SQL生命周期 | enforce；库存上限不是短窗的数据库降级证明 |
| entry.public / 全部外部请求，含重试/失败 | IP网络 | 固定窗口 mutation6000/60s、query10000/60s；POST ACK归control而非发送 | 窗口+5s；每域16384主体，定长计数器实现宽松入口 | observe；读本机有界保护，写按动作故障政策 |
| login.ip / 密码/邮箱会话登录 | IP网络 | SW300/60s | 65s；16384主体 | observe；故障503，不能降低为任意放行昂贵密码计算 |
| login.source / 同上 | 登录标识摘要×来源网络摘要 | SW10/60s；失败另计SW5/5min；成功只重置连续失败链，不删除尝试窗 | 失败链300s，尝试65s；32768组合 | observe；故障503；标识不存在也同路径/错误，禁止全账号永久锁 |
| otp.entry / V验证码申请/校验入口 | IP网络 | SW120/60s申请、300/60s校验（分动作） | 65s；16384主体/动作 | observe；仅验证过原SQL限额的路径允许受控DB降级，否则503 |
| post.create / CREATE与实际重试发布 | 账号 | SW5/60s + 30/1h，逻辑操作 | 最大窗+5s；每账号最多30事件 | observe；可在明确只依赖既有120/60s最终限额的语义下受控降级，不承诺保住新增5/30精确值 |
| comment.publish / CREATE/RETRY评论 | 账号 | SW12/60s + 120/1h，逻辑操作，允许少量连续回复 | 最大窗+5s；每账号最多120事件 | observe；同上，既有SQL120/60s保持 |
| dm.send / 文字或单张图片发送 | 账号 | TB容量30，补充2 token/s，1逻辑消息扣1（多图逐张） | 满桶后空闲TTL60s；单主体定长 | observe；故障503（4096库存不能证明频率） |
| dm.conversation.create / SendDMText隐式创建新身份对 | 账号 | SW10/10min + 40/1h；实际新会话1次 | 最大窗+5s；每账号最多40事件 | observe；故障503；已有会话/重放不扣创建 |
| upload.attempt / 帖子、评论、头像raw PUT、DM图片PUT | 账号（全部用途共享） | SW60/10min；每次实际传输尝试1，重传也计 | 605s；最多60事件/账号 | observe；故障503；与逻辑send不混为同一单位 |
| upload.bytes / 同上 | 账号（全部用途共享） | SW120MiB/10min + 512MiB/1h；实际接收wire body字节 | 最大窗+5s；64KiB计费块、每主体最多8192有效块，必须合并/上限控制 | observe；故障503；先body读取准入再分块扣，不按Content-Length预扣/退款 |
| read.account / feed、详情、评论、DM目录/pending/controls/media | 已验证账号 | TB容量180，补充6/s，每请求1 | 空闲60s，定长 | observe；允许本机容量4096主体、TB60+3/s有界降级 |
| read.control / ACK/read/原任务和回执查询 | 已验证账号 | TB容量300，补充10/s，每请求1，独立于read/send | 空闲60s，定长 | observe；本机4096主体、TB100+5/s；保留收件/核对恢复通道 |

新增数值依据：帖子5/分钟用于比评论12/分钟更严格；评论允许12次短连回复；私信30突发/2每秒覆盖正常聊天和多图9张；创建会话另限制10/10分钟；上传120MiB/10分钟允许一次9张10MiB原图加少量重试，512MiB/小时允许多轮；DM base64传输开销必须计入，9张10MiB的wire已接近120MiB，观察时重点调参。读取每秒6并允许180突发，控制流更宽，覆盖4秒轮询、多身份分页和滚动；IP只宽松抗洪，仍须用校园共IP正常场景测出误伤再调。上述理由是试运行假设，不是流量观测结果。

内存总边界候选：每域最多32768活动账号/组合状态、16384网络主体；去重最多131072标记，单主体单动作最多256标记；Redis专用maxmemory256MiB、noeviction，越界新写503，不逐出已有计费状态。各动作有界集合，清理/到期与扣减同原子调用；按实际序列化MEMORY USAGE测量上界后再定最终maxmemory。大量upload.bytes块可能先触及总界限，阶段2必须改成有界精确合并表示或合理缩小容量，**不能把该草案视为已证明内存安全**。读降级满map拒绝新主体，不通过随机驱逐绕过。

去重TTL候选24小时；仅代表热去重缓存，不授权24小时后重新执行。永久SQL回执/锚点仍保留。短窗事件过期与去重过期分离；去重容量先于扣费检查，满容量503且不扣逻辑额度。Redis TIME/统一服务端时钟、脚本版本及cluster hash-tag须阶段2定稿。关联账号多规则需同slot，禁止跨slot半扣。

## Redis故障与恢复（必须实现，不以注释代替）

- 明确区分timeout/连接断开/OOM/脚本错误/已知数据丢失；未知执行结果不当作未扣。失败统一503 `SERVICE_UNAVAILABLE`，不要返回429、累计违规或永久业务失败；记录动作级错误/降级/耗时。
- 普通读可使用上表有界本机保护；写只有经真实DB回归证明覆盖的最终限额路径能受控降级。帖子/评论DB120不是新增5/30/12/120的等价物，交付必须明确降级不承诺共享新阈值。私信频率、上传流量、密码计算不得因库存或幂等表存在就放行。
- 已知状态丢失通过generation/哨兵与运维恢复协议检测；哨兵丢失不能由首个API自动初始化为“空额度”。恢复不能立即发放全额新桶并忽略故障前窗口；采用隔离恢复/最长有效窗口守候或持久化锚点方案，阶段2选择并测清。冷启动新环境初始化必须显式。
- 有限连接池、请求超时（候选100ms，需观察）、有限重试，脚本超时或网络timeout后不盲目重放扣费；熔断与恢复探测必须有界。观察模式Redis失效也需明确是否高成本503，与真实拦截故障策略一致，不能静默长期失明。
- 指标按低基数action/mode/outcome/error_class记录 requests/allow/would_deny/deny/redis_error/fallback/latency；不把账号/IP/邮箱/键摘要放label。Redis/日志不存验证码、密码、令牌、正文、邮箱→社区账号或账号→全身份映射。

## 验证入口和阶段2必须锁定的决策

现有测试入口（均本阶段NOT_RUN）：

- Go包 `internal/authprivacyhttp`：`strict_test.go` 的 `TestNetworkIdentityAndIndependentBudgets/TestNetworkBudgetConstructorRejectsMissingOrUnboundedPolicy`，及 `posts_endpoints_test.go/comments_endpoints_test.go/session_endpoints_test.go`；业务 `internal/authprivacy/*posts_test.go/*comments_test.go/*direct_messages_test.go/*direct_message_image_limits_test.go/eligibility_otp_test.go`。
- 真实隔离SQL/TLS：`services/api/authlab/run-runtime-isolated.sh`、`run-comment-text-isolated.sh`、`run-dm-chat-isolated.sh`、`run-post-images-isolated.sh`、`run-identity-avatars-isolated.sh`。只用本任务明确创建的一次性开发库，绝不连接既有运行库或重置未知库。
- Flutter `apps/mobile/test/post_controller_test.dart/post_api_test.dart/post_storage_test.dart/comment_http_test.dart/comment_runtime_test.dart/comment_journal_test.dart/dm_reliability_test.dart/dm_chat_races_test.dart/dm_http_fixture_test.dart/dm_lifecycle_test.dart`。新增429重启恢复、手动草稿、保序/取消、ACK不阻塞、字节重传测试。
- API完整校验：`python packages/openapi/check-specs.py`、`python tools/check-community-text-contract.py`、`python -m unittest discover -s tools/tests -p test_community_text_contract.py -v`；受影响Go build/test/vet、Flutter analyze/test、既有产品CI须补Redis真实服务任务，不能仅内存替身宣称A1–A6。

| 决策 | 阶段2验收边界 |
| --- | --- |
| 原子接口 | SW/TB、多窗口、多动作、内容指纹、dedup、TTL、容量一体；new conversation以DB确实存在性判定，与并发事务协调，避免重复创建计费。 |
| 跨Redis/SQL崩溃 | 明确account可信验证发生位置、SQL回执先查、Redis成功后DB失败/超时、SQL成功后Redis丢失/过期；准入后失败不退和同键只扣一次可同时验证。 |
| 内存 | 精确滑窗事件有界、上传wire字节分块和全局容量（包含攻击者无限幂等键/登录标识）；noeviction、OOM与已知丢失不能等同空状态。 |
| 故障恢复 | 不依靠进程内fallback声称跨实例精确；设置可证明的恢复屏障，避免Redis恢复瞬间超发，保留ACK/查询可用性。 |
| 协议 | 429前置拒绝与既有未知请求区别、Retry-After上限、auth与posts错误方言、409冲突优先级、永久回执的旧键重放。 |
| 客户端调度 | 限流/未知同会话阻塞、跨会话公平，持久notBefore、时钟回拨、确定未发取消、WAITING_FOR_REPLY人工重试，接收/ACK独立。 |

A1：两真实API同Redis，同窗口5次、20个不同并发，跨身份/API重启最多5，过窗恢复。A2：共享校园IP多账号+可信代理链/伪造头。A3：跨实例同键同内容并发一次额度/一次业务，同键异内容409，覆盖上述崩溃点与TTL。A4：正常滚动分页4秒DM轮询ACK、429草稿/队列视觉保留、上传截断/重传实际字节。A5：timeout/断连/OOM/flush或哨兵丢失/恢复，降级范围及Gate保持。A6：配置热/冷应用语义与off/observe/enforce、TTL/容量、Redis和日志隐私检查。全部本阶段 `NOT_RUN`。
