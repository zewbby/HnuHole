# 第5阶段：空批次预检最小修复与定点验证

2026-10-26，COMMENT-SNAPSHOT-REDIS-01。按调度指定的 GPT-6.1 Sol / high 实施[限定审查方案](stage-5-worker-precheck-review.md)。**最小修复完成，必要单项验证通过；第5阶段仍未满足性能验收条件，第6阶段未开始。** 未重新运行完整性能轮次、30分钟或真机项目，未提交、推送、合并或部署。

最终产品摘要 `4b0eef09c8ea55598b1f04828835926dcf4c8af91e268008b7ded8a924fc2807`，新建 API SHA `870950838141b4703f6627ee82ba06d39c4def15697bd9af32dbac116818cbca`。实际构建与测试源保存在 `/home/hnuhole/comment-snapshot-redis-20261024-8ed8f28/stage5-worker-precheck-r1/source`，与工作区对应源码逐文件匹配。

只修改三个产品/验证文件：[community_sessions.go](../../../services/api/internal/authprivacy/community_sessions.go)、[定点测试](../../../services/api/internal/authprivacy/community_session_results_precheck_test.go)、[既有CI工作流](../../../.github/workflows/comment-snapshot.yml)。生产代码新增31行：私有只读提示及清理函数开头分支。既有 `Snapshot` 起至函数结束，以及后续会话清理方法，按换行规范化后与原版本逐字一致；Gate、worker调度、SQL迁移、Redis协议和客户端均未改。

预检仅查询是否存在 `operation='SESSION_CREATE' AND state='LIVE'`；不判断到期时间、不缓存、不重试。子预算为 `min(50ms, 父剩余时间/10)`，不足1ms直接走原流程。只有查询及上下文均成功、确定不存在候选才返回0；提示错误/超时回原父上下文，父取消返回非成功。真实候选仍执行原最终Gate、可信时间及代次复核、事务和Abort。

## 实际验证

| 范围 | 结果与证明内容 |
|---|---|
| 编译、受影响包vet | PASS；构建 `cmd/api`，vet `internal/authprivacy` / `internal/authprivacyruntime`。 |
| W1 空批次/取消 | PASS；无候选、10000永久墓碑加其他operation、冻结Gate均不调用Gate，不改变数据或anchor；取消及非法limit正确返回错误。 |
| W2 真实候选/保留/批量 | PASS；未到期LIVE仍走完整Gate，`limit+1`到期候选按批处理；锁住候选按原SKIP LOCKED并在释放后清理；永久墓碑、NULL清理及原键不可复用不变。 |
| W3 错误/预算 | PASS；真实表独占锁使提示超时，释放后原父context完成清理；真实SQL缺表错误恢复后回原路径；连接池占满、关闭及查询后父取消均无假空成功或连接占用残留；200ms父上下文下提示至多20ms及小预算跳过已检查。这里的不可用项是关闭连接池，未冒称停整个数据库服务器。 |
| W4 并发到达/重新构建 | PASS；未提交插入对提示不可见，提交后新建Community下一次调用清掉；两个清理调用并发处理集合，批量未超限、无漏项/重复计数。验证的是重建服务对象及持久候选，不冒称操作系统进程重启验收。无跨调用缓存另由源码核对。 |
| W5 最终Gate/补偿 | PASS；已有冻结、选键后冻结、选键后恢复到新代次、ahead anchor均拒绝清理；需要业务事务收尾时原Abort仍执行，冻结持久化；原真实Gate checkpoint前/后取消收尾定点用例通过。 |
| W6 调度/竞争机制 | PASS；从真实Community worker注册中选择本任务，使用原RunOnce验证批量/deadline/单次观察；另一事务持有Gate行锁时，空任务仍返回且无Gate调用，非空任务必须等待到期/失败，释放后可清理。既有worker并发、取消、截止及退避定点测试通过。 |

一次新建私有socket、非超级用户的一次性 PostgreSQL 夹具执行，`-race -count=1`：**15个顶层测试PASS，0 FAIL，0 SKIP**，authprivacy包30.263秒。同行authprivacyhttp包因筛选无匹配测试，明确不计为已测试。所选用例和日志SHA见[机器证据](stage-5-worker-precheck-execution-evidence.json)。第一次即通过，未反复整轮或扩大测试范围。

实际命令使用已存在的工具和隔离runner：

```sh
go build -o <本任务私有目录>/bin/api ./cmd/api
go vet ./internal/authprivacy ./internal/authprivacyruntime
COMMENT_TEST_PATTERN='^(TestSessionResultPrecheck|TestSessionResultCleanupPreservesPermanentTombstone$|TestDurableWorker|TestGateCancellationBeforeCheckpointRollsBackPostgres$|TestGateCancellationAfterCheckpointCompletesPostgres$)' \
  sh authlab/run-comment-text-isolated.sh
```

runner内部只运行上述命名测试并启用race；此次未调用它的默认完整测试模式。CI新增同样筛选步骤，后续PR可触发；本轮没有远端CI结果。

## 实际收益与局限

已经验证的收益是**每个确认空的批次省去原来的Snapshot、CommitAuthorized、Abort三次Gate接口调用**，避免该批次竞争共享Gate行/anchor。未到期LIVE结果的单项仍为三次调用，实际清理的安全路径没有缩短。10000墓碑的空调用约4.22ms，Gate行被锁住时空worker约3.23ms，仅为本次单调用诊断日志；没有新的稳定时钟性能预检，不把它们当P95或吞吐结论。

LIVE登录结果保持八天，因此有对应LIVE结果的正常负载不会命中这个空分支；查询遇历史行扫描/池等待超过短预算会回退，并产生至多该名义预算的附加等待。它是局部空闲优化，不能推断解决全部worker竞争、每次评论读取的双套完整授权或Redis固定操作成本。

并发新增候选可能多等一次原调度机会：本轮剩余工作、原间隔/退避及下一轮前序任务都要计入。没有更改原任务deadline、批量、退避、可信到期、补偿或留存。既有阻塞文件锁与独立Gate收尾仍意味着不存在任意故障下的绝对墙钟清理保证；本次不宣称补齐这一既有边界。

**剩余验收条件：** 旧冻结6fb版本兼容回复预览/展开汇总+5.832%/+5.090%的失败保持原结论；新的4b0e版本没有完整P95裁决。修夹具、观测及本次空worker优化都不允许把历史失败改标PASS。后续由调度决定如何处理这一条件；本轮没有重新开启整轮性能测试的授权。

**收尾：** 测试夹具已结束，独立检查本任务运行时进程及临时comment-text PostgreSQL服务均为0；原 `tsc`、timesyncd active/enabled保持，本轮未改系统设置。之前30分钟、Redis/SQL容量故障、共享限流和真我证据保留各自版本/范围，未重跑、不迁移为新API证据。其他146项模块台账保持不变。
