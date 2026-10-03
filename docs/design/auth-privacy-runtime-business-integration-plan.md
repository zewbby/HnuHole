# C/V 开发服务与业务授权接入实施计划

日期：2026-10-01。规划时范围与必要决策已收口；随后用户授权按 T0–T6 实施，当前代码与 runner 已落盘，编译和动态验收因本机缺工具仍待执行。实际状态见[实施／验证记录](auth-privacy-runtime-business-integration-validation-report.md)。下文保留规划时的范围、顺序与完成标准，“拟新增”路径的当前状态以报告为准。

## 1. 目标、范围与约束

**目标：**把已经完成的隔离认证模块装配成可重复启动的独立 C/V 开发服务。Flutter 经真实 HTTPS 完成注册、登录及恢复后，从接入 C Authorization Safety Gate 的真实目录读取七个通道；无需客户端持续轮询也能有界推进签名、退役续办、注销释放和清理。

**范围：**服务配置与启动、开发 PKI／密钥／Gate 引导、正式版本化迁移及权限、Mailpit 真实 OTP、持久后台任务、目录授权事务、目录续期元数据的移动端持久更新、进程级联调和交付说明。现有密码登录、恢复码、会话、七天注销与可选 Passkey 的服务端规则沿用，不重做产品访谈。

**范围外：**V 独立可信时间／旧快照冻结实现、设备与恢复凭据管理页面、原生 Passkey 桥、帖子／评论／私信、正式部署、真实存量账号迁移、历史业务内容清理／通知、生产独立授时／锚点基础设施、双主体运营及人类独立安全评审。设备／Xcode 验收可以在另一电脑并行进行，实测前继续列为未验收。

**方法：**先建立可用迁移与非 owner 运行连接，再装配服务；抽取最小授权业务事务，使认证复核、目录读取和续期同事务提交；复用现有状态机推进持久任务，不发明第二套 OTP、会话或通道数据源。

**约束：**

- 只基于 `codex/auth-privacy-handoff`。计划源基线为 `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`，当时本地与 origin 一致；新会话先核对实际 HEAD／工作区，不覆盖他人改动。
- 当前 checkout：`/Users/zewbao/Desktop/workspace/Hnuhole/remote-auth-privacy-handoff`。其他电脑使用该仓库自己的绝对路径，不能在外层工作区误操作。
- 用户确认只处理全新开发库；旧通道升级仅在一次性临时库验证。不得连接或清理未知数据库、真实账号数据。
- C 认证与业务保持同一 PostgreSQL 数据库、同一事务；V 使用独立进程、数据库、运行凭据和签名／恢复权限域。同机开发隔离不构成生产双组织独立证明。
- C Gate 保持全部认证读写 fail closed、5 秒回退容忍、5 分钟证据 TTL、单受限恢复角色、显式签名恢复及 generation 推进。API 启动不能自动将 FROZEN 改为 OPEN。
- Windows 与 macOS/Linux 均提供明确开发步骤。Windows 的 Go 服务和隔离验证运行在 WSL2，基础设施使用 Docker Compose；Flutter／Android 可在 Windows 宿主机。此片不做原生 Windows Go 文件锁适配。
- 沿用 Goose、sqlc、oapi-codegen、宿主机 Go／Flutter 与 Compose 基础设施；限定工具版本。`go.mod` 声明 Go 1.22、现有 Compose 使用 PG16；历史实测为 Go 1.27.1／PG18.6，不能外推兼容性。执行前核对并实测声明版本；若确需提高最低版本，记录原因并更新基线，禁止静默采用 latest。
- 大型验证运行时、构建缓存和 APK 已按用户要求清理。本轮不下载、不重建；实施时优先复用另一电脑现成工具，输出可复现命令和小型脱敏证据。只删除本次创建且可确认归属的临时产物。

四项已确认决策见[第 40 轮](../discussions/2026-10-01-grilling-round40.md)。

## 2. 实际缺口与阅读顺序

新会话先读本计划、[HANDOFF](HANDOFF.md)、[最新原生／真实联调报告](auth-privacy-mobile-native-integration-validation-report.md)、[Safety Gate 设计](auth-authorization-safety-gate.md)、[迁移设计](auth-privacy-database-migration-design.md)及[实验 README](../../services/api/authlab/README.md)。涉及具体规则时查对应 OpenAPI 与当前实现，不从历史节点重新推导需求。

| 现有文件／符号 | 已核实的现状 | 本片应得到的结果 |
| --- | --- | --- |
| `services/api/cmd/api/main.go` | 装配旧 `auth.SessionValidator` 与目录 router | C 新认证与目录统一入口，无旧认证回退 |
| `internal/auth/postgres.go`、`internal/httpapi/router.go` | 旧表校验 token 字符串摘要，再独立查询目录；无 Gate／账号状态／代次 | 按新 token 规范与最终事务授权，只接受 `c_auth` 会话 |
| `internal/channels/postgres.go`、`service.go` | pool 查询，完整目录排序／校验已有 | 接收同一授权事务，显式 `public.channels`，保留完整校验 |
| `internal/authprivacy/community_sessions.go` | `sessionView` 有账号→限制→会话锁与最终 Gate；返回账号后事务已经结束 | 可复用的最小业务授权事务边界 |
| `internal/authprivacy/authorization_gate.go` | `Snapshot`、`CommitAuthorized`、`Abort` 已实现 | 复用最终提交与独立冻结，避免业务回滚抹掉冻结 |
| `internal/authprivacyhttp` | C/V 公共／内部处理器、mTLS 对端已存在，只由实验装配 | 实际可启动进程、受控公开路由及独立内部监听 |
| `services/api/migrations` | 仅已发布演示会话和七通道 | 新增 C 正式迁移；V 独立迁移序列；不修改历史 SQL |
| `services/api/authlab/migrations` | 完整实验 SQL；runner 重置一次性 schema；运行角色仍是表 owner | 版本化可升级迁移、独立 migration owner 和受限 runtime |
| `infra/docker-compose.yml` | 单 PG16／单库及 Mailpit | 明确 dev 标签的 C/V 分离数据与凭据、loopback 端口 |
| V `ResumePendingConfirmations`／`DispatchMail` | 有界续办存在；投递接受原幂等键、DB 只存摘要 | 有界持久任务调度及按摘要推进的受控邮件 claim |
| `apps/mobile` 的目录 repository／controller | 只返回通道列表，未持久处理目录续期 header；已有请求 fence | 持久更新当前会话权威截止后发布节点 |

下文标注“拟新增”的路径、接口和 runner 目前不存在，应由执行会话创建与验证；现有接口名不代表可以直接拼接完成授权。

## 3. 分步实施与各步验收

### T0：锁定基线、依赖和开发安全边界

核对分支、HEAD、工作区及磁盘；盘点现有 Go／Docker／Flutter／Android／Xcode 工具及 race 所需 C 编译器／CGO，不重新下载整套工具链。登记 OS 与版本，把平台未执行项单列；缺少依赖不能关闭 race 代验收。整理 C/V 各自配置清单：DB 连接、公开／内部监听、固定公共 origin、mTLS peer／信任钥、签名与加密钥、超时、限流、worker 上限；C 另有独立证据／锚点／恢复材料配置。

输出更新后的 `infra/README.md`、`services/api/README.md` 与 `.example` 配置（文件名拟新增，需在实现中统一）。示例只能是无秘密样例，启动必须拒绝缺失／错误钥、对端、证书和 schema。健康检查区分进程存活与可授权就绪；C 冻结时仍可诊断，但受保护路由全部拒绝。时间证据过期不可悄悄改用 DB 时间。

同时登记 V 当前直接使用 `clock_timestamp()` 的 OTP、预算、确认／签名、配额和清理放行点，以及旧快照风险。V 独立 Gate 留作下一片；文档明确本片的 V 仅供开发，C 的 Gate 验证不能作为 V 灾备安全证据。

**验收：**配置负向测试覆盖缺字段、错钥／错证书、错误 origin、错误 DB／schema；本片无秘密入库到普通配置、日志或 Git。版本兼容结果有实测依据。依赖：无。

### T1：正式迁移、角色与一次性升级验证

在 `services/api/migrations` 新增 C 迁移，将 `authlab/migrations/community` 的完整当前约束纳入 Goose；为 V 建独立序列（拟新增 `services/api/verifier-migrations`）。编号由现有正式序列递增，不能覆盖已发布 `0001_sessions.sql`／`0002_channels.sql`，不能把测试 reset SQL 当启动迁移。保持迁移源唯一，更新实验装配以测试正式结构，保留历史验证来源说明。

数据仍是 C 的 `c_auth` 与 `public.channels`、V 的 `v_auth`。不移动／复制通道，不重建 UUID 或 code，不凭旧 account_id 伪造资格、用户名、密码。独立 NOLOGIN owner／受控迁移连接与 LOGIN runtime；runtime 无 DDL、角色管理权限或 owner membership。显式 schema USAGE、必要 DML／sequence 权限，C 仅对目录授予所需 SELECT。普通业务读／审核／导出角色不得读认证材料；V 角色不得读 C。

全新开发库的 C Gate 从冻结状态建立，后续显式开发签名恢复。旧演示升级在临时库验证：保存七通道数据基线、扩展新结构、验证约束、停旧认证签发、撤销旧 `public.sessions`／撤 runtime 旧表权限、接入新路由。旧表删除另做收缩迁移，不放本片；无兼容 validator／视图。

**验收：**空库迁移、重复执行不重复种子、失败原子回滚、旧七通道逐字段／UUID 保持、新注册登录可用、旧 token 即使 account_id 与新账号相同也拒绝；实际 runtime 全链运行。权限负向测试证明 owner 分离、业务角色／跨方／旧表访问拒绝，覆盖 Gate audit identity sequence。已消费资格或撤销后的事实不能用普通 Down 回滚；应用故障采取冻结和前向修复。依赖：T0。

### T2：C/V 服务启动、开发 PKI 与真实 OTP

升级 `services/api/cmd/api` 为 C 入口；拟新增 `services/api/cmd/verifier` 为 V 入口。从现有 `CommunityEndpoints`／V endpoints 装配 public TLS 和独立 internal mTLS server，限定真实 TLS peer，不接受转发头伪造证书。明确启动失败、监听错误、请求／SQL deadline、信号处理、停止受理、worker 停止与 graceful shutdown 顺序。迁移使用独立连接／命令，不让 runtime 自动执行 DDL。

Compose 提供分离 C/V PostgreSQL 服务及 Mailpit，数据卷和端口明确标为本项目开发资源，端口绑定 loopback。宿主机服务通过 literal loopback 的已发布 SMTP 端口连接 Mailpit，遵守现有 `SMTPProvider` 仅 loopback 可明文的限制。OTP 正常生成、加密排队、真实 SMTP 投递与验证；拟新增开发取码工具只读 Mailpit 测试邮件，限定开发模式和本机权限，不在 C、公共 API 或生产客户端暴露取码能力，不将 OTP 写日志，不使用万能码。

拟新增开发引导工具在私有开发目录生成两方独立密钥、公开 TLS／内部 mTLS 材料与 C 开发证据；配置显式信任固定测试根和 SAN。沿用已验证的 Dart 兼容 TLS 类型，协议签名仍保持现有算法。不能关闭证书验证。Gate 恢复、证据续发和代次变化走已有受限签名协议，不由 API 持有恢复签名权限或自动解冻；工具明确标为同机开发信任，不冒充独立授时／运营锚点。

为 macOS/Linux 和 Windows＋WSL2 分别写首次初始化、启动、停机、重启与故障诊断步骤，包括 Docker 与 WSL2 连接、路径归属、端口和证书信任。设备访问涉及 origin/SAN/网络暴露时单列实际环境步骤，只开放明确的开发监听，不能随意扩大整个基础设施端口。

**验收：**实际进程启动后 HTTPS 与 mTLS 正反向检查、Mailpit OTP 完整注册、错 peer／过期证书／错 origin 拒绝、服务重启数据保留、Gate 冻结启动无授权、证据停止更新后 fail closed；退出无泄漏进程。依赖：T1；worker 装配依赖 T3。

### T3：有界后台推进、邮件未知结果和留存

复用 V `ResumePendingConfirmations(ctx, limit)` 与 C 现有注销、outbox、ACK、清理命令。拟新增 scheduler／worker 装配，每次有上限、独立超时、有界并发、错误退避和停止取消；多个实例使用已有终态 CAS／数据库 claim，锁顺序与 HTTP 一致。参数有明确保守默认值与配置校验。

V 邮件任务增加受控按持久摘要认领／推进的内部接口（拟新增接口，不能声称已有）：数据库只保留原 key 摘要，不能为了 worker 存回原幂等键或生成新业务 ID。claim 在外发前持久进入 DISPATCHING；SMTP DATA 结果未知维持 UNKNOWN／DISPATCHING，不自动重投，也不假设 SMTP 有幂等去重。已过期邮件材料及时擦除，不能通过重启重新延长 OTP 或风控预算。

C 自动推进到期注销、已提交终态的收据签名／投递、持久 ACK 和有界清理。网络／SMTP／签名器调用在业务锁和 SQL 事务之外进行；结果只 CAS 原任务。ACK 本地提交才开始留存，重复 ACK、重签或迟到回调不改起点、不复活已 ACK 事件。永久槽位／请求摘要终态保留；会话摘要以服务端最终有效期算清理。C 后台授权／清理遵守 Gate；V 暂沿用自己的现有时间规则并显式登记限制，不能借 C 时钟授信。

特别改造 `internal/authprivacy/outbox.go`：现有 `ReceiptJob`／`StoreSignature`／`RotateReceiptEpoch` 未经 Gate，`DeliverReceipt` 仅末尾 `recordACK` 经过 Gate，`CleanupAcknowledged(ctx,before)` 无 Gate、无批次上限。增加有界 outbox 枚举；任务读取／认领、签名落库、epoch 变更及 ACK 后清理各自经最终 Gate 事务与 CAS，清理截止来自最终 trustedAt 和已持久 ACK 起点。仅在 scheduler 调用 Snapshot 后直接执行旧 pool.Exec 不满足要求。保持 `recordACK` 最终 Gate 与终态核对。

冻结停止新的调度与本地授权提交；已经认领并在途的签名／mTLS 外发无法撤回。V 已提交的收据事实不回滚，本地 ACK 因 Gate 拒绝时保留原任务，恢复后重试同一收据／用途并取得幂等 ACK。不宣称两个数据库与网络副作用原子提交。

**验收：**多 worker 竞争、claim 后崩溃、SMTP 明确失败／DATA 未知、签名器故障、退役原确认续办、ACK 丢失／ACK 本地提交前崩溃、迟到回调、重启续办、清理后旧请求拒绝；冻结发生在 claim 前／签名在途／V 已处理而本地 ACK 前／清理最终提交前分别验证。证明不重复发送未知邮件、不重复释放、不重置留存；批次／超时／资源上限可观察。依赖：T1，装配到 T2。

### T4：目录在 C Gate 最终授权事务内读取

从 `community_sessions.go` 的 `sessionView` 提取最小共享账号→限制→会话锁与最终状态验证，保留所有旧接口行为。拟新增 `internal/authprivacy/community_authorized.go` 和 `WithAuthorizedSession` 一类受控内部边界；精确类型在实现时定稿，不把现有 `AuthorizeExistingSession` 返回 ID 当作业务授权。避免借用会额外锁全部凭据／意图的 credential transaction。

HTTP 边界先按当前 session 入口规范解析 Bearer：缺失／错误方案401，非规范编码400；只有合法32B能力进入业务命令。事务顺序必须为：Gate Snapshot →按解码后字节摘要只读定位账号→账号、限制、当前会话锁→复查归属→同事务读完整目录并校验→`CommitAuthorized` 最终可信时间下复核 ACTIVE／处罚／会话及 authorization generation／撤销／到期→更新活动和阈值续期→提交→写 HTTP 响应。不能散列 token 字符串冒充新规范。目录业务回调只能通过所提供事务查询、构造内存结果，不能提交、写响应或调用网络。所有失败沿用 Gate `Abort`，保持独立上下文的持久冻结。

将 `channels.PostgresRepository` 缩窄为可由 pgx.Tx 满足的查询能力，显式 `public.channels`；复用完整七通道校验与排序，失败无部分结果、不续期。最终可信时间判定仍有效的同一会话，剩余≤7天才更新到最终裁决时间＋30天；不改 token、撤销能力或 session generation，不取消注销，不续 PENDING_CLOSE／CLOSED／封禁／过期会话。并发续期不累计天数。

将 `/api/v1/channels` 接到 C 公共边界，扩展现有 method/preflight 路由表；淘汰启动路径的旧 validator／`requireSession`，新认证故障时也不能回退旧表校验。可保留历史源码供追溯，但不可到达旧授权入口。

**验收：**第 4 节确定性 SQL 并发／故障矩阵；旧 authlab 全回归。目录请求先完成最终提交可以成功；撤销先提交则拒绝，不能承诺撤销会追回已经提交的响应。依赖：T1，先于最终服务与移动端联调。

### T5：OpenAPI 与移动端权威续期衔接

更新 `packages/openapi/channel-api.yaml`：200 body 保持现有 `{channels:[…]}`、七条记录和五字段 `id/code/name/initiallyVisible/displayOrder`；增加 `Session-Expires-At` 权威截止 header，格式沿用 C 会话契约。目录不返回账号／私有用户名／代次／安装 ID。401 缺失／无效等沿用现有错误码，被新设备接替使用 `session_replaced`；Gate／证据／锚点／DB／提交未知为 503 `SERVICE_UNAVAILABLE`，完整目录不可用为 503 `CHANNEL_DIRECTORY_UNAVAILABLE`。

统一现有 `error:{code,message,details?}`＋`requestId`、服务生成的 `X-Request-ID`、`Cache-Control:no-store`。公共 wrapper 的 400（非规范能力头／raw query）、403（Origin）、429（网络限流）也纳入契约与客户端回归，不能实现新增状态而文档仍只有 200／401／503。验证 OpenAPI 生成／漂移检查使用锁定工具版本，生成方式落地在 README；不引入与实现无关的批量生成重构。

目录 repository 返回带列表与权威 expiresAt 的内部结果（拟新增类型），controller／认证协调层在同 token／requestVersion fence 下先持久更新 AuthStore 的当前会话截止，再发布节点。迟到目录不能更新后来的登录、恢复、退出或新请求；持久失败沿用现有 fail-closed，不发布节点。401 清当前权限与节点，503／网络故障保留安全持久 token、无节点可重试。仅真实前台正常请求续期，无后台定时保活。

**验收：**真实 TLS header 解析与非法／缺失截止拒绝、请求 fence、退出／换机与迟到响应、metadata 写失败、401／503／新增边界状态；Flutter analyze／test。改变现有真实 C/V mobile fixture 的目录 503 占位，使用真实 handler；另保留显式故障注入的 503 测试。依赖：T4。

### T6：实际启动闭环、平台记录与交付

拟新增 `services/api/authlab/run-runtime-isolated.sh`：创建明确归属的一次性 C/V 数据资源，通过正式迁移、非 owner runtime、实际 cmd 进程及真实 HTTPS／mTLS／Mailpit 验证。实现后 README 给出精确执行命令；该 runner 目前不存在。使用随机可用端口、受控私有目录、信号 trap；不得启动时清理未知现存资源。

闭环至少包括真实 OTP 注册→恢复码完整确认→新会话→七通道目录→目录阈值续期及重启→换机旧机拒绝→定向退出→独立恢复后旧会话拒绝→Gate 冻结／显式恢复后旧代次拒绝→七天到期关闭／V 处理释放／C 持久 ACK。时间边界使用受控测试证据／数据，不等待七天，不更改生产接口增加万能控制。

全部既有回归、迁移／最小权限与 T3–T5 故障矩阵通过后更新验证报告、机器记录、`infra/README.md`、`services/api/README.md`、`services/api/authlab/README.md`、`apps/mobile/README.md`、`docs/design/HANDOFF.md` 和 `docs/design/progress.md`。新报告拟为 `docs/design/auth-privacy-runtime-business-integration-validation-report.md`，小型机器记录拟为 `services/api/authlab/runtime-business-integration-verification.json`。明确执行 OS、版本、代码 SHA、命令／退出码及未执行项，不把仅编译、测试 fixture 或 mocked storage 写成设备完成。

**验收：**本计划完成清单全部映射到证据；只保留小型脱敏日志摘要／JSON，销毁本轮临时库、进程、密钥与产物。依赖：T2–T5。

## 4. 授权并发与故障矩阵

使用确定性 SQL 锁／测试 barrier 控制交错，不靠 sleep 碰运气。取锁后的最终可信时间和提交顺序才是权威。

| 场景 | 必须证明的结果 |
| --- | --- |
| 接替／定向退出／重设／申请注销／封禁先持账号锁并提交 | 目录随后401；不返回数据、不续期 |
| 目录先持锁并最终提交，然后撤销／关闭／处罚 | 已提交目录可成功，随后请求拒绝；无反向死锁 |
| Snapshot 后 Freeze 先完成最终 Gate 锁／提交 | 目录503；无成功 body；业务回滚不消除冻结 |
| 目录最终提交后才 Freeze | 本次成功有效，后续503 |
| 锁等待跨到期、处罚边界或 generation 推进 | 最终 trustedAt 判定；旧代次不复活；恢复后新登录可读取 |
| 缺失／非规范／合法随机／合法过期 token 与已冻结 Gate 组合 | 缺头／错误方案仍401、非规范编码400；合法32B能力进入 Gate 后503，与 session 入口一致 |
| 多个目录并发跨≤7天阈值 | 同 token，按最终时间＋30天，不累加；>7天不延期、过期不续 |
| 目录少条／重复或非法 code／SQL故障 | 503，无部分目录，无续期 |
| 锚点落盘故障、提交结果未知、请求取消 | 无成功输出；独立冻结和显式恢复遵守既有规则 |
| 旧 public.sessions 有效、相同 account_id、旧字符串散列 | 新路由均拒绝；runtime 旧表无权限 |
| metadata 持久失败、旧响应晚于退出／新登录 | 无旧节点／权限发布，不污染新会话 |

## 5. 执行验证命令与平台边界

以下命令已存在。实施会话在具备依赖的环境从 `services/api` 执行并登记退出码；先聚焦修改处，再运行完整检查，禁止把未执行当通过：

```sh
sh authlab/run-isolated.sh
go test -race -count=1 -p 1 ./...
go vet ./...
```

移动端从 `apps/mobile` 先执行 `flutter pub get`，再运行现有 `flutter analyze`、`flutter test --reporter expanded`。普通 Flutter test 不包含 `integration/`；Go 测试没有 `AUTHLAB_MOBILE_FLUTTER` 会跳过 Dart 联调，不能据退出0称其已通过。真实 mobile runner 需先指向同运行平台的 Flutter：

```sh
# services/api；Go fixture 与 Flutter 必须在同一运行平台
export AUTHLAB_MOBILE_FLUTTER="$(command -v flutter)"
sh authlab/run-mobile-isolated.sh
```

原生设备／iOS 的现有脚本与配置以[最新平台报告](auth-privacy-mobile-native-integration-validation-report.md)和移动端 README 为准。macOS 可从仓库根目录运行 `sh packages/auth_vault/test/native/run-installation-marker.sh`，仅证明文件标记回归。Android 当前 checkout 没有 Gradle wrapper，须先做标准 Flutter 构建生成配置，不能把报告中的 `./gradlew` 说成 clone 后直接可执行。新的运行时 runner、迁移／生成校验命令在实现后提供，不能拿上述 httptest 实验当实际 cmd 启动证明。没有工具或设备时把具体目标交给另一电脑验证并列为缺失证据，不能自行降低完成标准。

Windows 路径已确认使用 WSL2：Go、文件锚点、开发密钥和 POSIX runner 在 WSL2 Linux 文件系统中执行，不放在未验证的 `/mnt/c` 等 Windows 挂载目录。Docker Desktop 的 WSL2 集成或 WSL 内 Docker 按实际环境记录。Windows 宿主机 Flutter／Android 用于 app 构建和设备运行；现有 Go fixture 会直接 exec Flutter 并生成 Linux 路径配置，headless 联调必须使用 WSL2 内 Linux Flutter，不能直接传 Windows `.bat` 路径。Linux SDK 来源／版本和清理方式在运行说明中登记，优先复用验证电脑现有依赖，不在本机恢复大型缓存。若未来要 Go 原生 Windows，须另片实现和验证文件锁、原子替换与持久落盘语义。

macOS/Linux 步骤保留真实 TLS 与文件权限，并记录所用文件系统。iOS 仅 macOS 完整 Xcode 环境可验收；Windows／Linux 不能代签该项。Android instrumentation／完整 app 与 iOS Keychain 目前仍待设备执行，可以并行，不能用本片纯 Dart 证据替代。

## 6. 完成标准、后续顺序和回退

本片完成需同时具备：

- C/V 实际进程可按两类 OS 的确认方案启动，配置／TLS／对端错误拒绝，开发 OTP 闭环真实执行。
- 正式迁移与最小权限验证通过，临时升级保持七通道，旧认证无法到达；新环境不带演示 token。
- 持久后台任务有界且重启安全，SMTP 未知不重发、终态与 ACK／留存不回退。
- 每个目录授权与业务读取／续期通过 C Gate 的同一最终事务；并发、冻结、恢复与故障矩阵通过。
- Flutter 实际读取七节点，权威截止先持久化，过期／替代／故障／迟到响应不能误授权。
- 已执行完整必需检查，未执行平台项有明确记录，报告／机器记录／交接文档相互一致。

达到上述条件意味着开发服务与第一条受保护业务读取闭环完成，可继续补设备／凭据管理与原生 Passkey，随后进入身份／发帖主链。V 独立 Gate 应作为独立安全切片尽早完成，在任何生产放行前必须落实；原生设备验收可并行。生产还需独立授时和锚点、真实灾备、双主体运营、留存操作及人类独立审计，本片不能直接证明可生产上线。

应用或迁移故障时保留权威终态、撤销与 generation，冻结并前向修复；不回退旧 validator、不从旧库开放、不删除正式数据。实施拆分为可检查的小提交，是否推送／部署由新会话的用户指令确定，本计划不授权外部发布。

资源清理按本次资源清单逐项执行；数据库与开发私钥默认位于明确私有临时目录／标记 dev 卷。不得笼统 `docker system prune`、对未知 Compose 项目 `down -v`、删除现成 SDK／AVD 或用户数据。报告记录清理范围与剩余路径，Git 不提交缓存、数据库、PKI 私钥或 APK。

## 7. 新会话接续提示

> 在 Hnuhole 项目中，只基于 `codex/auth-privacy-handoff`。先阅读 `docs/design/auth-privacy-runtime-business-integration-plan.md`、`docs/design/HANDOFF.md` 与计划列出的现有设计／报告，按 T0–T6 实施 C/V 可启动开发服务、正式迁移与最小权限、后台任务及目录接 C Safety Gate 的真实闭环。沿用第40轮确认：V Gate 另片，只处理全新开发库与一次性旧通道升级验证，提供 macOS/Linux 与 Windows＋WSL2 的步骤。不要重做已收口 grilling，不扩展到管理页面／原生 Passkey／帖子。复用现成工具，避免大型下载和验证缓存；验证完成清理本轮临时数据。运行计划要求的检查、更新验证报告／机器记录／docs/design/HANDOFF.md／docs/design/progress.md，报告实际代码 SHA、执行平台与剩余门槛。开始前检查本计划与工作区是否有新改动，发现事实不一致先依据代码修正执行步骤。
