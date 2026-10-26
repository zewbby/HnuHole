# 第5阶段：登录结果清理空批次预检限定审查

2026-10-26，COMMENT-SNAPSHOT-REDIS-01。调度指定 GPT-6 Astra / xhigh 审查，下一步由调度切 GPT-6.1 Sol / high 实施。**本轮审查完成；下列收紧条件纳入最小实现后，可以实施。尚未修改产品代码或运行测试，第5阶段未完成，第6阶段未开始。**

审查对象是 [针对性修正记录](stage-5-targeted-execution.md) 中的 `Community.CleanupSessionResults` 提案。所读工作区在 `codex/feat/comment-snapshot-redis`，HEAD `c05198155543b8d1a259dc41fdeb860126dee7d0`；当前产品摘要仍为 `0481b785fdc3e06583feaec2fd8707a96e10648465b5deada8a5256cea0ee9ab`，已有 API SHA `0c419619356c5f916c4fa81ace90ce8a9cf242581944aa94cffc9b13126a7d67`。它们属于前轮构建，本轮没有新二进制。审查不提升历史 P95、30分钟、真机或模块裁决。

## 结论与必须收紧的条件

1. **成功查明没有任何 `SESSION_CREATE / LIVE` 行，才可省略这一批的整个清理调用。** 这条只读提示不判断到期、不读秘密、不锁候选行、不产生业务效果，也不创建授权凭据。`LIVE` 存在但尚未过期时仍进入原流程；查询异常、超时或结果不确定均不能按“空”处理。不得加入 `now()`、进程时间、缓存的可信时间或 `SKIP LOCKED` 作为提示过滤条件。
2. **原提案缺少预检自己的短预算，应补上。** 直接用父 `ctx` 查询，可能在连接池、DDL锁或历史墓碑扫描上消耗完整任务时限，使本来应该执行的清理无法开始。建议单次提示预算最多50ms，且不超过父上下文剩余时间的十分之一；计算出的提示预算不足1ms时跳过提示，直接走原路径。该数值是本次最小实现的保守上限，不是测得的性能结论。不得重试、后台查询或增加任务总时限。
3. **只能承诺保留原有调度和事务界限，不能写成“最多2秒清理”。** `Run` 是整轮完成后才等待间隔；任一任务失败会让整轮退避。现有 Gate 还有独立收尾上下文及无 context 的阻塞文件锁，已有代码并不提供任意故障下的严格墙钟清理上界。此优化不得放大批量、轮询间隔、退避、任务 deadline、Gate 收尾时限或数据留存窗口；不能把“不改这些参数”描述为新增的绝对及时性证明。

按这些条件，未发现该空批次分支会绕过实际清理的最终 Gate、授权代次、可信时间复核、回滚或冻结持久化。性能效果必须保持未定：现有诊断证明了多个 worker 的总体竞争，尚未单独证明这个任务是主要贡献者。

## 代码依据及边界

| 边界 | 当前源码事实与本次要求 |
|---|---|
| 实际清理 | [community_sessions.go](../../../services/api/internal/authprivacy/community_sessions.go) 的 `CleanupSessionResults` 先验证1–1000的 limit，再 Snapshot、begin、defer Abort、`FOR UPDATE SKIP LOCKED` 选键，最终在 `CommitAuthorized` 回调按 `final.TrustedAt` 再判到期并 UPDATE。预检插在 limit 验证后；有候选时以上整段保持原样，包括选不到键也照旧收尾。 |
| 无业务效果的空分支 | 不曾建立 Gate/业务事务，不需要为它调用 Gate Abort；只读 SQL 自身的连接/取消收尾必须完成。不能在空返回前写结果、移动高水位、释放额度或启动异步补偿。 |
| 候选完备性 | 用同一 `c.pool`、同一权威数据库及权限，每次调用重新执行一条语句。不使用副本、新连接配置、长事务旧快照或跨调用空值缓存。无 RLS 新策略、无新授权角色。 |
| 原留存语义 | `createSession` 将结果到期设为可信时间加8天；墓碑触发器禁止删除、复活或改变身份绑定。新提示不改任何列，因此无未到期记录会被提前清除、过期键也不会被重用。正常站点最近8天有登录结果时往往会走原路径，这项优化只覆盖完全没有对应 LIVE 行的情形。 |
| 永久墓碑增长 | [0003_authprivacy.sql](../../../services/api/migrations/0003_authprivacy.sql) 只有 operation/key 主键及 key 唯一索引，没有匹配 `state='LIVE'` 的专用索引。`EXISTS` 找不到候选时可能检查大量历史行；`LIMIT 1` 也不能约束负结果的扫描量。此次依靠短预算回退，不宣称查询为常数成本，不顺带加迁移或索引。若定点验证显示提示频繁超时，记录此收益限制。 |
| 冻结与观测 | 空批次可以返回 `(0,nil)`，即使 Gate 已冻结；这只表示没有清理工作，不表示授权系统健康。真实候选仍必须拒绝冻结/陈旧代次。其他任务和 `/health/ready` 的 Gate 检查不改，不能把这个 worker 的 `Failed=false` 当作 Gate 健康信号。空路径本身不负责发现或持久化原本尚未被访问发现的外部冻结。 |
| 其他效果与补偿 | 不修改共享准入、会话创建/续期、评论 SQL→Publish、Redis 原子额度、旧快照兼容、原清理器、Abort/冻结补偿。实际清理失败仍由原 deferred Abort 收尾。 |

## 最小实现交接

仅在 `community_sessions.go` 增加一个私有提示 helper 和函数开头分支；新增定点测试与它们的既有隔离 SQL CI 入口。生产 worker、Gate、迁移、配置和公共 API 不改。

提示 SQL 固定为：

```sql
SELECT EXISTS (
    SELECT 1 FROM c_auth.request_results
    WHERE operation = 'SESSION_CREATE' AND state = 'LIVE'
)
```

建议执行顺序：

1. 保留既有 limit 验证及其错误优先级。父 `ctx` 已取消/到期时返回非成功结果，可沿用 `ErrAuthorizationUnavailable`；不把取消当空批次。
2. helper 从父上下文派生一次短 context：预算 `min(50ms, remaining/10)`；无父 deadline 时为50ms，预算不足1ms时直接返回“未证明空”。同步执行 `c.pool.QueryRow(...).Scan(&exists)`，不持有连接进入后续 Gate。
3. 在取消子 context **之前**保存查询错误及子 context 状态，然后释放它。只有查询和子 context 均成功、`exists=false`、父 context 仍有效时返回“已证明空”。子查询超时/SQL失败等属于“未知”，继续使用原父 `ctx` 执行原流程；不得把已取消的提示 context 传给 Gate，也不得续一个新的总 deadline。
4. 调用者在返回空前再检查父取消。父取消为错误；已证明空为 `(0,nil)`；其余接回现有 `decision, err := c.gate.Snapshot(ctx)`，后面的实现不移动、不抽取授权、不添加第二个空键捷径。
5. 提示失败但原清理成功时，结果仍由原清理决定；原清理也失败时照原样传出非 nil 错误，让现有 worker 统计和退避生效。不要为提示错误新增独立重试或全局退避。可在测试中计数提示失败，无需为此增加含 SQL/行标识的生产日志。

不要求新增全局开关或可注入的公共 API。测试同步优先用已有 `AuthorizationGate` 包装器、真实 SQL 事务及 pgx tracer；若需要测试 helper，通过包内窄接口或未导出函数注入，禁止全局可变测试钩子。

## 并发、恢复与清理时限

**并发到达。** 提示在自己的语句快照中得到 false 后，有事务才提交新的 LIVE 行，本批可以无工作返回。下一次调度会重新查库，不能沿用 false，因此一个已经提交且持续 LIVE 的候选不会因这个提示连续漏掉。旧路径也可能在选键语句之后错过新提交，但新方案的取样点提前了；某些原来本轮能看到的到达会多等一轮，不能称严格时序等价。若提示 true 后候选被另一 worker 清掉或锁住，继续原来的有界 `SKIP LOCKED` 与最终 Gate，允许本批清零条，不进行第二次越权捷径。

**调度上界。** 设提示返回后本轮剩余耗时为 R，现有轮后等待为 D，下一轮此前任务耗时为 P；下一次提示机会是 `R + D + P`（另含正常调度开销），不是 D。成功轮 D 为配置 Interval，失败轮最多配置 MaxBackoff；默认为2秒/30秒，实际 runtime 可覆盖。真实清理再受原批量、待处理积压、行锁、Gate 可用性和收尾影响。此次只保证不新增退避/缓存等待，且每次附加提示名义预算不超过50ms并计入原 task context，至少预留进入时剩余预算的90%。这不保证原来恰好卡在 deadline 前的工作仍必然成功。

**既有绝对时限缺口。** [workers.go](../../../services/api/internal/authprivacy/workers.go) 的 `TaskTimeout` 是任务 context，不是强制终止线程；[authorization_gate.go](../../../services/api/internal/authprivacy/authorization_gate.go) 的 Snapshot/commit/Abort 使用原有独立10秒收尾，[authorization_evidence.go](../../../services/api/internal/authprivacy/authorization_evidence.go) 的 `withLocked` 使用阻塞 `Flock(LOCK_EX)`，不接收 context。不能从15秒默认任务预算推出“整轮≤任务数×15秒”，也不能保证暂停进程一直持锁时仍限时清完。这是已存在、此次不扩大的边界，不在本轮擅自重写 Gate 或锁协议；如要求故障下绝对秒数，须另行明确SLO并审查共享锁/收尾设计。Redis快照回收的原有界限是另一个机制，不受本次登录结果提示改变。

**重启与中断。** 不记录“已扫空”、游标、水位或已完成标记。提示之前/期间/之后崩溃都不改变持久候选；重启后 `Run` 先 RunOnce，再按原规则等待。实际清理开始后崩溃沿用 SQL 原子提交、永久墓碑和独立 anchor 一致性检查；不改变它们的恢复路径。数据库恢复为旧视图时，空提示也不会授予权限；一旦有业务效果仍须由原 Gate 检查数据库/anchor/evidence，空返回不能宣告恢复成功。

## 必要单项验证（下一轮实施后执行）

以下以全新、明确归属的一次性 PostgreSQL/真实 Gate 为主。未执行不能标 PASS；无 DSN 跳过不是 SQL 通过。使用命名测试和 `-run`，失败只重跑修复直接影响项，不运行 campaign、30分钟或真机验收。

| 编号 | 定点验证及通过条件 |
|---|---|
| W1 空分支/取消 | 空表及只有 EXPIRED 墓碑/其他 operation 的表返回0；用计数 Gate 验证 Snapshot/Commit/Abort 均未调用，SQL及anchor无变化。invalid limit保留原错误；父取消返回非成功。冻结 Gate 下空分支也不能改冻结状态或被记为健康证明。 |
| W2 候选/保留/批量 | 未到期 LIVE 必须走 Gate但不清理；真实过期 `limit+1` 行首轮最多清 limit、次轮清余项、再下一轮走空提示。锁住的候选按原 SKIP LOCKED，释放后后续可清。沿用 `TestSessionResultCleanupPreservesPermanentTombstone`，核对所有应清元数据为NULL、原键永久拒绝复用及会话/额度无变化。 |
| W3 错误和提示预算 | 真实 ACCESS EXCLUSIVE 表锁使提示超过子预算；用 Gate 包装器在回到原流程时释放锁，证明父 context 仍可用且实际清理成功。另测连接池占满/父取消、SQL查询错误（仅影响提示的注入），均不能返回假空；连接释放且无挂起goroutine。断库时最终非 nil。不要依赖机器恰好50ms定时，用事件与宽容测试超时证明控制流/上限配置。 |
| W4 并发到达/重启 | 事务A先插入但不提交，另连接调用提示见空；A提交后下一次调用必须经Gate清理。再构建新的Community/worker复用同一持久库与anchor，证明没有缓存空值。两清理调用并发处理已到期集合，无重复状态变更或遗漏；仅在必要处用进程子测试证明重启，不安装App。 |
| W5 最终授权/补偿 | 真Gate在有候选时预先冻结必须拒绝；用测试包装器在选键后、原 `CommitAuthorized` 前冻结或推进代次，必须不修改结果，原Abort执行。受控损坏/ ahead anchor 在有候选时仍fail closed并保留冻结。复用相关真实Gate取消收尾测试覆盖该函数继续调用原实现，不重跑整个授权矩阵。 |
| W6 调度/收益机制 | 通过一次有界 `RunOnce` 检查该任务无重试、批量与deadline仍取原配置；复用现有worker取消/退避定点测试。在已冻结的Gate行被另一事务持锁时，空提示调用仍可返回、非空路径必须等待或失败；同时记录空/非空/墓碑负载的提示结果与Gate调用数。这直接验证省掉空批次竞争，不据小样本时长宣布HTTP P95通过。 |

建议测试放入 `community_session_results_precheck_test.go`，统一前缀 `TestSessionResultPrecheck`。最小执行集合为此前缀、既有墓碑测试、`TestDurableWorker*`，以及与W5实际使用收尾路径相符的 `TestGateCancellationBeforeCheckpointRollsBackPostgres` / `TestGateCancellationAfterCheckpointCompletesPostgres`。按最终改动执行gofmt、受影响包编译/vet及上述race用例。为新SQL测试接入现有一次性库CI设施；当前 authorization-gate workflow 的路径过滤仅覆盖Gate文件，不能假设仅改community_sessions就会触发它。本地不必为了接线而运行旧整轮runner。

本轮只做源码与文档静态审查；W1–W6全部 `NOT_RUN_REVIEW_ONLY`。后续实现可以直接依此执行，不再请求用户确认。历史 P95 失败保持；没有授权本轮或下一步重开完整性能轮次。完成上述最小修复/单项验证后先交付事实，不能自动宣布第5阶段或整体迁移完成。
