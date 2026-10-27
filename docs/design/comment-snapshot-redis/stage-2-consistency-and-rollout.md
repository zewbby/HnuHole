# 评论分页快照迁移第 2 阶段一致性与发布设计

> **2026-10-26 修复后的配置边界：** 交付模板createBackend=postgres、readPostgres=true、readRedis=false；省略配置及DefaultConfig也保持PG。Redis双读、新建及关闭PG读取，须在可靠环境性能项处理完成并取得启用授权后才执行；当前不部署或启用。测试夹具仅在归属明确的隔离Lab中显式选Redis，与发布默认分离。R6-01–03已实现且定点验证、有限复核通过，阶段6完成；下一步为阶段7 PR及适用CI；性能原FAIL保留，详见[当前计划](execution-plan.md)。

> **2026-10-26 发布限制更新：** 用户已允许性能延期以继续代码审查和PR，但尚未允许启用Redis。下文的双读、Redis新建、停PG读取步骤暂不执行；当前默认应为PG/ReadRedis=false，唯一示例的开启值已列为R6-02待修复。可靠环境性能项处理完成并取得启用授权后才执行发布步骤；不在本机追加性能或搭环境。原协议和历史数据格式设计保留，最终v2 packed实现及验收范围见阶段5记录和[当前计划](execution-plan.md)。

工作项 COMMENT-SNAPSHOT-REDIS-01，2026-10-24，Asia/Shanghai。调度指定 GPT-6 Astra / xhigh。本阶段仅设计与设计验证，不实现产品代码、不运行数据库或设备、不提交或发布。基线、接口盘点沿用 [第 1 阶段](stage-1-baseline-and-interfaces.md)，产品约束以 [V1.1](requirements-v1.1.md) 为准。

## 确定的架构

评论业务继续在最终 Gate、账号锁和 PostgreSQL 事务内读取当前权限与内容。Redis 仅保存临时名单。创建使用“保守预留与写入候选 → SQL 明确提交 → Redis 确认发布 → 返回签名游标”的顺序，没有跨 Redis/SQL 的虚构事务，也没有运行时静默回 PostgreSQL。

采用有界模块名录记录每份预留的账号、大小、期限和状态，用一次带绝对过期时间的 SET 更新该名录；名单正文分别存为不可变字符串。正常翻页不读取整个名录。新建和发布通过脚本串行更新名录，失败可以暂时多计，不能少计实际仍占用的数据；清理先删候选数据，成功后才能释放名录中的预算。

默认部署独立的社区快照 Redis 进程，复用共享限流的依赖、装配和运维模式。理由是现有限流候选没有模块总字节上限，无法证明把快照塞进同一个 256 MiB 示例实例不会挤占限流。共享限流任务仍统一负责公共 Redis 接入与部署装配；快照预算和业务实现归本需求。独立进程不是 Redis Cluster，也不改变 C/V 隔离。本次有实际取舍的决策记录于本目录内的 [ADR 0001](adr/0001-isolated-instance-and-conservative-reservations.md)。

## 不变量

1. 只有 SQL CommitAuthorized 明确成功、Redis 发布明确成功的创建结果，才能向 HTTP 层返回有效快照及签名游标。
2. 每份名单一旦分配随机 ID，就不改变成员、顺序、归属、排序类型、创建时间或到期时间；ID 不复用。临时置顶属于客户端展示，不写回名单。
3. 每个仍可能占用物理内存的名单值，都必须已有名录预算预留。未知写入不能按失败直接退额；删除被确认前不释放预留。
4. pending 和 active 都占账号额度和模块预算。跨实例原子准入，不能依赖进程 map 或仅靠当前 SQL 锁来保证 Redis 额度。
5. 所有名单与临时名录都有绝对到期时间；读取、重试、确认发布均不延长名单的创建后 1800 秒期限。
6. 单份缺失、过期、错归属或非法游标为 CURSOR_INVALID；存储通信、控制信息或名录完整性故障为存储不可用，不能混用。
7. R 游标永不探测 PostgreSQL。PG 游标只在显式兼容读取开关允许时读取旧表；无匹配结果也不生成新名单继续旧偏移。
8. 本模块不访问限流键，不改变限流 policy/hash/generation，不沿用其 verified-db 降级或计费恢复屏障。

## 配置与隔离

runtime 的 `CommentsConfig` 增加可选 `snapshots` 配置；旧配置省略该项时维持原 PostgreSQL 路径，不能自动开启 Redis。新配置项如下，名称在本阶段固定，数值中的试运行预算仍须第 5 阶段实测确认。

| 字段 | 本期语义或初始候选值 |
| --- | --- |
| createBackend | `postgres` 或 `redis`，明确发布开关。 |
| readPostgres / readRedis | 显式控制可接受的游标来源；redis 新建要求 readRedis=true。不能因错误临时改开关。 |
| ttlSeconds / maxIDs | 严格为 1800 / 10000，不作为任意可调排序或保留策略。 |
| maxPerAccount | 初始候选 1024；必须满足 10 页各 50 条且每条有回复的验收。 |
| maxSnapshotBytes | 初始候选 196608；采用紧凑二进制 ID 列表，10000 个 UUID 为 160000 字节，另加受限头部。 |
| maxModuleBytes | 初始候选 67108864，包含名录与控制元数据固定预留。不是只有 key 个数限制。 |
| maxLedgerEntries / maxLedgerBytes | 初始候选 8192 / 4194304，限制脚本扫描及解析工作量；所有解码先检查字节数。 |
| ledgerFixedReserveBytes | 初始候选 12582912，计入模块预算，覆盖名录、重写和固定元数据的保守预留。 |
| redis.address / username / passwordFile | 快照专用连接与私有凭据；不借用 C/V 限流运行身份。 |
| redis.namespace / epoch | namespace 例如 `hnuhole:comment-snapshot:v1:dev:`；epoch 为初始化时显式生成的随机 UUID，不按 API 启动随机重置。 |
| redis.deadlineMilliseconds / poolSize | 初始 100 ms / 8；每次 Redis 往返有界，go-redis MaxRetries=-1，连接池等待计入期限。 |
| operationBudgetMilliseconds | 初始 500 ms，累计本次服务端存储往返及恢复查询耗时，SQL 本身保留原期限，所有调用仍受外层请求期限约束。不能将 500 ms 墙钟期限直接跨 SQL 执行间隔耗尽；截止也不代表服务器脚本已经停止。 |
| prepareLeaseSeconds / cleanupIntervalSeconds | 30 / 10；受理发布必须在租约内，健康存储下失败候选目标在 60 秒内收敛。 |
| cleanupBatchSize / clockSkewMilliseconds | 64 / 2000；每条原生 DEL 命令最多 64 个 key，SQL 可信时间与 Redis TIME 超过允许偏差则拒绝新建。清理每轮最多处理 maxLedgerEntries 个候选，总期限初始 5 秒。 |

模块费用采用 `roundUp(2 * payloadBytes + keyBytes + 4096, 4096)` 加固定名录预留，覆盖名单值、Redis 分配开销和预留条目。此式是保守记账模型，不冒充 MEMORY USAGE 的实际测量；第 5 阶段必须证明选定 Redis/allocator 下物理开销不超过预留，否则增加预留或缩小预算后复验。

独立快照实例开发示例候选 maxmemory=128 MiB/noeviction，模块预算 64 MiB；生产或既有环境的地址、内存及主机余量由公共负责人配置，不把示例当已部署。若将来有已验证的双模块硬预算和延迟隔离证据，才允许显式配置共享实例；不在本期默默改动限流实例策略。

运行时校验必须拒绝：非 C 服务启用、所选 createBackend 没有对应 read 开关、未知 backend、零 epoch/复用限流前缀、无界池/期限、ttlSeconds 或 maxIDs 偏离固定值、预算小于固定元数据预留、名录条目/字节无界。正常发布配置还须容纳至少 501 份十页场景；测试内部可用小限额验证竞态，但不能把该小配置作为用户默认。

快照 runtime 最小命令范围为 GET/SET/DEL/EXISTS/TYPE/PTTL/TIME/EVAL/EVALSHA、必要 INFO/PING 与客户端握手；访问 key 仅限快照前缀。operator 额外按初始化/测量需要开放 SCAN、MEMORY USAGE 和 CONFIG GET，不给 runtime CONFIG/FLUSH/全域 key 权限。NOSCRIPT 仅允许回退到同一已审查脚本的 EVAL，不允许隐藏写重试；脚本不使用 Redis 8 专有选项。

## Redis 数据结构

完整 key 都由 Go 根据已验证环境和用途构造，并通过 KEYS 显式传入脚本。脚本不能从名录动态拼 key 或做无界 SCAN。

| Key | 内容与生命周期 |
| --- | --- |
| namespace `control` | 固定大小的版本/epoch/configHash/ledgerUntil/READY或DRAINING 控制信息，初始化工具显式建立。这是持久配置元数据，不是永久临时快照或账号索引；不保存评论名单、账号列表或凭据。 |
| namespace `ledger:{epoch}` | 有界紧凑 JSON 名录。条目含随机 snapshot ID、账号用途摘要、requestKey/requestScopeDigest、候选 token 摘要、payload 摘要、bytes charge、created/expires、prepareUntil 及 pending/active/aborting。SET PXAT 至全部条目最长名单到期时间加 60 秒。 |
| namespace `data:{epoch}:{id}` | 有界不可变字符串：版本、账号用途摘要、post/root/kind/sort、created/expires、ID 数量、原始 UUID 顺序及用途隔离 MAC。创建即 SET PXAT 到 trustedCreated+1800 秒，之后不改值、不续期。 |

账号配额由名录中该账号未释放条目计算，不另建永久账号索引。名录最多 8192 项，且受字节数与总预算双重限制。snapshot 值不含正文、邮箱、令牌、点赞状态或额外身份关系。

data 的 MAC 使用现有评论 codec 的用途隔离输入域 `HNUHOLE/COMMENT-SNAPSHOT-DATA/V1`，覆盖 epoch、snapshot ID、固定二进制头部与完整有序 ID；不能用不带密钥的 checksum 代替，也不能把同账号同帖另一名单的合法值挪到当前 key。Load 先验 MAC、长度、数量、来源与归属，再使用 ID。当前内容回读还须核对每条 comment 的 PostID 与 RootCommentID 属于请求范围，不能仅因 Redis 头部声称属于某帖就放行其他帖的 ID。名录不信任冗余计数，按合法有界条目重新计算账号和字节合计，异常字段 fail closed。

control 的 configHash 包含数据格式、epoch、用途密钥承诺及资源/租约参数，所有实例必须一致。发布的 create/read 开关不改变数据格式 hash；改资源配置需显式受控重配，不能让不同预算实例同时写。pool/transport 期限不参与数据意义。

control.ledgerUntil 是“可能仍有数据”的高水位：先将名录预留 SET 成功，再将 control 高水位推进成功，最后才允许 SET 名单。前两步部分成功时保守占额，不写未记账名单。清理完全部条目后保留带绝对 TTL 的空名录，直到高水位到期，不能主动删空名录造成误报丢失。只有 control 高水位已过且不存在潜在未到期数据时，才允许从空名录开始。高水位仍在未来却找不到名录，返回 503 并要求检查，不能当全新空额度。

control 丢失、类型损坏或 hash 不符不自动初始化。operator 可在停止本模块新建、确认归属后恢复名录或等待旧数据到期再换 epoch；不得清理限流 namespace。单份名单丢失无需修复名单，原游标明确失效。

## 创建与提交顺序

### 首次页面请求的重试身份

新客户端在一次“无 cursor 的列表加载”开始时生成随机 16 字节 nonce，通过可选头 `X-Comment-Snapshot-Request` 的 canonical base64url 传递。一次短重试与手动重试该次失败加载沿用 nonce；主动刷新、切换排序及重新进入使用新 nonce。服务端将 nonce、当前账号和环境做用途摘要作为 requestKey，另将 post/root/kind/sort 做 requestScopeDigest；同 requestKey 但范围不同明确拒绝。nonce 不代表登录或授权，不可用于跨账号恢复。跨 HTTP nonce 恢复适用于 Redis 新建；PG 兼容路径保持原表协议，仅在同一次 handler/事务内避免重复创建，不为此新增 PG 临时名单表。

旧客户端不传该头时，由服务端为本次 handler 生成 nonce，仅保证 handler 内短重试不重复预留。原请求成功响应丢失后，该次已提交且 active 的快照仍是有效占额，不凭“客户端没收到”退额。新客户端可用原 nonce 在 30 分钟内恢复同一快照；恢复不续期。再次创建始终使用新的随机 snapshot ID，不会在旧 ID 下重建名单。

### 正常创建

1. 进入原 withCommentSession/withPostSession，在账号锁和最终 Gate 回调内核对帖子、根评论及当前读取权限，使用原排序算法获得 ID 名单。
2. Redis Prepare 检查 control READY、参数、可信时间、已有 nonce 及预算。若同 nonce 已 active，复用原名单；仍重新在当前 SQL 授权中读取当前可见内容。服务端在首次 Prepare 前固定随机 snapshot ID、attempt token 和完整候选内容；同 handler 短重试全部沿用。同 nonce pending 且 attempt token 相同可补完本次未确认的步骤；不同 token 的另一 handler 在租约内返回存储暂不可用，不偷换候选、不另扣额。
3. 新建时先以单次 SET PXAT 提交包含 pending 条目的新名录，再推进 control 高水位，最后 SET NX PXAT 写不可变名单。每个写步骤都可能失败，不能依赖 Lua 错误回滚此前写入。所有步骤在有界脚本内执行，外部看不到脚本中间状态，但错误留下的预留必须按真实状态处理。
4. Prepare 返回私有候选 handle；页面数据仍在同一 SQL 事务/Gate 内读取，session renewal 与 CommitAuthorized 按原流程完成。此时不发送响应、不向调用者发布候选游标。
5. 仅 CommitAuthorized 返回明确成功后，调用 Redis Publish(handle)。它检查候选 token、payload 摘要、归属和 prepareUntil，单次 SET PXAT 将名录状态 pending 改 active；不改 payload 或其 TTL。重复 Publish 同一 handle 幂等。
6. Publish 被确认成功后才生成并返回 V2 签名游标。若 Publish 响应丢失，一次受控恢复查询能确认已 active 且完全匹配时可返回；否则返回 503，不伪装成功。

账号锁和 SQL Gate 内最多包含有统一预算的 Prepare/Load 调用；Publish 与补偿发生在 SQL 事务完成之后，不为了重试长时间占用授权锁。原 begin/CommitAuthorized/Abort 负责 SQL 事务，快照 Store 不提交业务事务或另开授权事务。

### 失败补偿和回收

- SQL 回滚、授权拒绝或 commit 结果未知：本次新建 pending 候选不发布，启动一次独立短清理；不返回候选游标。SQL read/session-renewal 即使实际提交，也不要求保留未发布的名单。
- Abort 只能清理匹配 token 的 pending，不能清理同 nonce 已发布的 active。对未到期 pending，必须先用原子名录提交将它改为 aborting，再删除 data；Publish 只接受 pending，不能越过 aborting。Publish 与 Abort 竞争：前者先成功则 Abort 拒绝，后者先成功则 Publish 拒绝，不能在查询 pending 后直接 DEL 与发布竞争。
- 对已过 prepareUntil 的 pending，Publish 已永远禁止；对已过 expires 的 active，读取也已禁止。可在只读脚本核对这些固定期限后，执行原生 DEL，再以单次 SET PXAT 从名录删条目/释放费用。Release 必须检查对应 data 已明确不存在及状态/期限；中间失败只多计，不少计。不能只看时钟就从名录删条目而放任物理过期值延迟回收。
- 后台每 10 秒执行一次有界回收轮：最多读取 maxLedgerEntries 个到期 pending/active 或 aborting，以每条 DEL 最多 64 个 key 批量删除，再一次有界 Release 合并核销已证实不存在的条目。所有 Release 访问的 data key 显式列入 KEYS；不按 10 秒只释放 64 个条目而让大批失败候选长期占额。每轮受 5 秒期限与最多 8192 条目双重约束，健康时 60 秒收敛目标仍须实际压力验证。
- 只读的有界清理候选查询使用 Redis 7 no-writes 脚本；OOM 下可通过原生 DEL 释放已确定可删的 pending 数据，名录缩减写失败继续保守记账，待内存恢复再核销。创建/发布脚本采用 Redis 7 shebang/no-cluster，禁止 allow-oom；不能照搬旧式脚本在 OOM 下继续增大内存。
- 客户端取消不等于服务端已回滚，不能直接退额。SQL/Publish 已成功但 HTTP 响应丢失属于已提交结果未知，保留 active 并允许同 nonce 恢复；若用户放弃，其到期最多 30 分钟。明确未发布的失败候选按 30 秒租约和健康时 60 秒清理目标收敛。

## 读取和 Store 接口

`internal/commentsnapshot` 提供数据/引用/错误与 Redis 实现，SQL 适配器留在 authprivacy 以使用原事务。Community 的 commentServices 注入 router；HTTP 公共响应保留现有字段。

接口职责固定如下，具体 Go 类型实现时不得改变本节语义：

- `Prepare(ctx, scope, orderedIDs, trustedCreated, RequestIdentity, legacyCount) -> Prepared`：RequestIdentity 含 requestKey/requestScopeDigest；预留并保存不可变候选，返回随机 ID、来源、epoch、绝对期限、摘要、私有 attempt token 和 newlyCreated 标记。同 nonce active 返回 reused handle，不能覆盖旧值。
- `Publish(ctx, Prepared) -> Ref`：仅供 SQL 已明确提交的 service 调用，幂等发布；不延长期限。PG 路径由原 SQL commit 完成，不虚构第二个 PG 提交。
- `Load(ctx, scope, Ref, trustedAt) -> orderedIDs`：Redis 正常读取只校验小 control 与目标 data，不传回整个名录；检查签名引用的来源/epoch/期限、完整性、归属和最多 10000 ID。权限与当前内容仍在原 SQL/Gate 内查询。
- `Abort(ctx, Prepared)`：只对本次新建且仍 pending 的 handle 作有界补偿。cleanup 顺序遵守先删除后核销。
- `Usage/CollectExpiredPending`：仅用于新建配额检查、指标和清理，不能使普通翻页依赖全模块名录扫描。API 实例与后台清理共用原子协议。

`TextCommentPage.SnapshotID` 仍是原 16 字节 UUID 的 base64url，不在客户端重新解释来源。服务端 private SnapshotRef 携带 backend/epoch/ID/expiry/kind/sort；LocateComment 使用同一 private Ref 调 Load，不能从裸 snapshotId 猜存储或在两库间探测。返回的定位 cursor 包含明确来源。

对外 Load 引用必须来自已验证的签名游标；只有正在当前 SQL 授权回调内创建首个页面时，service 可以使用自己的私有 pending handle。裸 snapshotId 不是公开读取候选的凭证。由于 V2 游标只在 SQL 和 Publish 成功后签发，普通翻页无需为验证 active 状态下载全名录。

service 在 SQL 回调外保留私有 Prepared handle，便于 withCommentSession 出错返回空响应时仍能清理本次候选；reused active 的 newlyCreated=false，绝不被当前失败请求补偿删除。HTTP 序列化只在 Publish 后调用，不将私有 handle 或 token 加入公共 JSON。

## 游标协议和兼容读取

保留 V1：decoded 长度 52 字节、原域和签名验证，明确路由旧 PostgreSQL。旧 offset 上限 10000、账号/帖子/根评论验证继续。

新增 V2：canonical base64url 编码 78 字节，依次为 version 1 byte（2）、flags 1 byte、epoch 16 bytes（PG 固定零）、snapshot UUID 16 bytes、offset 4 bytes big-endian、expires Unix milliseconds 8 bytes big-endian、tag 32 bytes。flags 的 bit0..1 为 backend（PG=1/R=2），bit2 为 kind（MAIN=0/REPLIES=1），bit3..4 为 sort（relevant=0/recent=1/likes=2），bit5..7 必须零，回复只允许 relevant。tag 使用现有评论用途密钥和新域 `HNUHOLE/COMMENT-CURSOR/V2`，覆盖全部前缀。整数溢出、非 canonical、非法 flags/epoch、offset>10000、签名或期限错误统一拒绝。

V2 编码长度为 104 字符，同时小于客户端 PostProtocol.cursor 的 1024 字符上限及 OpenAPI 的 2048 字符上限，不扩大输入长度边界。

版本、来源与期限不能由未验证的前缀决定后备存储。验证签名后只访问所指向且当前配置允许读取的 backend；R 缺失为 CURSOR_INVALID，不转 PG。V2 PG 正常查询原表，并校验引用期限与存储行期限一致。V1 没有期限字段，仍以原表 expires_at 校验。

新兼容版本在 PG 新建模式也生成 V2 PG 游标，并使用本版 30 分钟/可配置额度。旧 V1 仍可能由旧实例创建，但只在全量兼容版本就绪前存在。回复预览与 expanded、limit 语义不改变；sort 只在首次主评论请求传入。

V2 续页的 kind/sort 来自已验签 flags，并与请求 MAIN/REPLIES 范围及 R 名单头部一致；不能把省略 sort 的续页误判成 relevant，拒绝合法的 recent/likes 续页。V1 PG 无排序位，沿用已冻结名单，不猜排序或重排。客户端用列表版本与原请求 cursor 阻止刷新/切排序前的迟到结果追加到新列表。

保留 0016 快照表、原权限和 CheckCommentSchema 的目录/权限核验，支持兼容和回退；本设计不新增 PG 临时名单表，也不删除或回滚历史迁移。readPostgres=false 后禁止的是业务名单数据读写、配额统计和过期清理，不以移除 Gate 或 schema 检查绕过要求。

## 配额在过渡期的口径

只计算当前发布配置仍接受读取的有效快照。双读且 Redis 新建时，在现有账号锁事务内查询该账号仍有效的 PG 数量，作为 legacyCount 传入原子 Redis Prepare；以 legacyCount + Redis pending/active 数量校验账号额度。所有新版本都遵守同一规则，不能用来源切换重复获得一份完整额度。

最终关闭 readPostgres 后，旧 PG 游标明确失效，legacyCount 固定为零，不再访问旧表做统计。明确回退并统一关闭 readRedis 时，旧 R 游标失效，PG 只统计仍接受的 PG 有效项；这属于发布开关回退，不是故障时的隐式降级。若回退仍保留 R 读取，则新建 PG 也须计入 R 有效项；R 不可用时该模式不能凭空忽略 R 配额。

## 错误契约和客户端恢复

| 错误 | HTTP / 稳定 code | 恢复 |
| --- | --- | --- |
| 单份缺失/到期、错归属、签名/偏移/已关闭来源错误 | 400 / CURSOR_INVALID | 提示用户刷新；单层回复只替换该层，主列表失效才替换主列表。 |
| nonce 格式不合法、同 nonce 被用于另一请求范围 | 400 / MALFORMED_REQUEST | 不自动重试，不泄露原范围。 |
| 名单超过 10000 ID 或 maxSnapshotBytes | 422 / COMMENT_SNAPSHOT_TOO_LARGE | 当前列表规模超限，仅影响该列表，不自动重试。 |
| 有效账号额度满 | 429 / RATE_LIMITED | Retry-After 为最早可能释放的 pending/active 或 legacy 期限向上取整，保持现有 1..86400 秒协议。 |
| 模块字节/名录容量不足、明确 OOM 拒写 | 503 / COMMENT_SNAPSHOT_CAPACITY | 提示稍后重试，保留内容，不循环自动重试。 |
| 超时、断连、未知写入 | 503 / COMMENT_SNAPSHOT_UNAVAILABLE | 保留页面，一次短重试仍失败显示局部手动入口。 |
| 名录/control 损坏、丢失或配置不符 | 503 / COMMENT_SNAPSHOT_INTEGRITY | 保留页面，不循环重试，记录运维错误并检查模块状态。 |
| 原 Gate/权限/不可见 | 沿用现有错误 | 保持原安全处理，不归类为可恢复快照故障。 |

HTTP 错误仍只含 error.code/message 和 requestId，no-store；不泄露账号、snapshot 归属或底层 Redis 错误。不复用 SHARED_RATE_UNAVAILABLE 表示快照故障。自动逻辑重试由客户端唯一负责：本地 TIMEOUT/网络故障或 COMMENT_SNAPSHOT_UNAVAILABLE 最多再发一次；Store/go-redis 不自动重发创建或发布。服务端在写入结果未知后最多执行一次只读状态核对，它不产生新预留或重复写入。容量、完整性、错签、权限和已确认失效不自动重试。客户端沿用 nonce 恢复无 cursor 创建，取消整个加载即停止后续自动尝试。

客户端第 4 阶段在现有严格解码和授权处理前识别新的 422/503 code，新增请求 nonce 头及需要的 CORS 白名单。API 包装不把快照 503 变成整体退出或授权不可用。一般翻页每次最多扫描三个原名单段，首次非空段可短页返回，游标按扫描而非展示条数推进；remainingCount 仍按名单剩余位置，不声称是实时可见回复数。

## 发布与回退步骤

1. 先核对并集成共享限流正式交付，完成公共部署接点。显式初始化快照专用实例/ACL/control/epoch，不让 API 自动初始化或重置配置。
2. 部署所有支持 V1/V2、PG/R 双读的兼容版本，createBackend=postgres、readPostgres=true。R 读取能力在初始化且健康后启用；保留限流新协议与数据库迁移。兼容期 PG 仍由原事务创建。
3. 全量实例确认兼容后统一 createBackend=redis；不能在仍有旧二进制时发 R 游标。短暂滚动配置期所有实例必须计入两种有效配额，并记录最后一个 PG 新建实例停止时间 T。
4. 等到 T+至少 30 分钟且全部 PG 快照已自然到期；确认不存在旧写入实例，再统一 readPostgres=false。此后旧表只保留 schema/回退实现，正常快照路径和配额/清理均不访问。
5. 回退时保留新二进制，通过明确开关统一改 PG 新建。R 可读且稳定时继续读旧 R；R 故障时统一 readRedis=false，旧 R 游标提示刷新。不得部署不认识共享限流围栏或 COMMAND_CLOSED 的老二进制，不回滚其迁移，不用旧偏移重建。
6. 若要换快照 epoch/资源 hash，先停本模块新建，等待或按归属证明清理旧数据，统一配置后再开启。不得清空共享限流数据，也不把快照恢复动作升级为限流恢复操作。

## 设计验证和交付边界

第 2 阶段验证覆盖故障表、预算模型、游标长度/版本可区分、保守预留与补偿状态机，以及所有阶段 1 接点映射。验证结果见 [机器记录](stage-2-validation.json)。这是设计模型与文档静态验证，不是 Redis/SQL、性能、真机或生产通过。

以下是实现验收的硬条件：所有注入失败点不能出现“有未记账 data”或“未授权提交却返回游标”；pending 崩溃须在健康时有界回收；未知发布能同 nonce 恢复；active 不能被普通 Abort 删除；两实例配额不超限；正常 Load 不读取全名录；脚本最大字节/条目数受控并通过真实 P95 门槛。若名录全量重写无法满足性能，须在保持不变量的前提下调整存储结构并复审，不通过调大超时掩盖。

第 3 阶段前共享限流仍是正式提交/合并依赖；本轮没有复制其未提交实现。真机可自行控制则后续验收，否则记录“真机验收待用户于 2026-10-25 验收”，继续非设备工作。

## 技术核对依据

Redis 脚本串行执行会阻塞服务器，所有 key 必须显式传入；因此限制名录大小和循环范围，普通翻页避免名录扫描。[Lua 脚本官方说明](https://redis.io/docs/latest/develop/programmability/eval-intro/)

SET 可以将值与 PXAT 期限一次写入，用于不可变名单和名录提交；仅使用 Redis 7 已支持的选项。[SET 官方说明](https://redis.io/docs/latest/commands/set/)

noeviction 在内存不足时拒绝增长性写入，不能代替模块预算。Redis 7 shebang 的默认 OOM 限制与 no-writes 标志用于区分创建和只读维护查询。[淘汰策略](https://redis.io/docs/latest/develop/reference/eviction/)、[Lua API](https://redis.io/docs/latest/develop/programmability/lua-api/)
