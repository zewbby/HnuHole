# Publish 状态字节优化实施与针对性验证

> **2026-10-27 PR80已合并 main：** 合并 `4e7b0fb7d05daa579eb37138d374bb495d4fea30` 与已测 head `a2e98eb` 完整tree一致，既有适用CI通过。一次指定性能场景PASS，历史FAIL及其他未验项保留；同机开发Redis已授权启用并保留PG旧游标读取，仓库默认仍PG，生产未发布。本次仅合并与文档收尾，无新产品测试、性能采样或部署。见[最终合并交接](merge-receipt-20261027.md)。下方待提交／未合并／未启用状态均保留原历史时点。

2026-10-27，COMMENT-SNAPSHOT-REDIS-01，GPT-6.1 Sol。基于 PR #80 的 HEAD `23a85991c620d4ddcfc11896e4e94a3d8096902c`，按一次 Astra/ultra 设计裁决实施。以下实施阶段记录的结束时点为本地未提交/推送候选；该时点 PR CI 对应旧 head，不代表本候选已获远端 CI 或成员批准。后续送审状态见文末。

## 实现

`services/api/internal/commentsnapshot/write.lua` 的 Publish 分支保留完整 readLedger 和原 owner/token/digest、PENDING、lease、expires、payload 等值检查。只有 header/control 水位及 PEXPIRETIME 三者相等且未来、原 expiryArg 可精确十进制表示、SET/PEXPIRETIME/SETRANGE 权限均满足时，以零基 `e.position+204` 写二进制 state=2 并立即返回。其他情况原样调用 save/SET PXAT；撤销 SET 不会被 SETRANGE 绕过。

原 SQL 提交成功后 Publish、probe、Abort、Release、额度/预算、固定到期及 v2 表示均未更改。示例 ACL 文档和三份实际进程夹具的快照运行权限增加具体 `+setrange +pexpiretime`，命名空间范围及限流权限不变；原 runtime ACL 测试保留旧清单，覆盖兼容回退。没有修改任何已有运行实例的配置或权限。

## 实际验证与失败保留

使用现有 WSL Linux 文件系统中的一次性源码副本、既有 Go 1.22.2 / Redis 7.0.15 / PostgreSQL 16.15 / Goose v3.22.1 工具与缓存。组件夹具逐进程验证 PID；SQL runner 只创建和清理自己的一次性私有 socket 集群，不连接现有业务库。依赖为离线复用，未安装新环境或改变系统时钟。

- 首次 `go test -mod=readonly -race -count=1 -timeout=120s ./internal/commentsnapshot ./cmd/commentsnapshotctl -v`：22 个顶层、38 个子例 PASS，1 个新顶层内的 wrong-token 子例 FAIL，0 SKIP。该夹具误把 token 写成64位 hex，实际规范是32字节 base64url，导致原参数检查先返回 ErrRequest。仅修正测试向量，产品代码不变；随后只运行该子例，1顶层/1子例 PASS。原 FAIL 日志保留，没有重新执行整套测试。
- 新增7组组件测试，覆盖首/中/末字节与旧 v2 writer 完整字节/期限等价、旧新 writer 混用、Abort/release 压缩后的移动位置、H/C/T不等及无期限回退、极大水位错误边界、旧/缺失/完整 ACL、撤销 SET、真实 noeviction OOM、非目标记录损坏、租约到期、ABORTING、载荷/身份不匹配、旧 JSON 拒绝、写前/成功回包丢失后 probe、真实 AOF 关闭重启回放。命令统计断言正常 Publish 增加1次 SETRANGE、0次 SET；回退恰好相反。回包丢失使用客户端 Hook 注入错误，Redis 状态由真实进程执行，不冒充实际网络故障装置。
- 首轮既有回归还覆盖并发额度、补偿失败、受控到期、DRAINING、固定快照期限、保守预算及独立 Redis 限流域。套件内既有 `TestRealRedisSnapshotOperationMeasurements` 顺带执行了一次500样本纯组件测量（约1秒），没有重跑；其日志只属于组件结果，未作为 API/SQL/PG 对照或达标证据。
- 真实 SQL：通过既有 `run-comment-text-isolated.sh`，将 `COMMENT_TEST_PATTERN` 限定为 `^TestCommentSnapshot(RedisSQLPublicationCompatibilityAndRecovery|RepliesAndCombinedQuotaPostgres)$`，两项 PASS、0 FAIL/0 SKIP。涵盖真实延迟 COMMIT 失败后不暴露快照、补偿恢复预算、Safety Gate 冻结、配额与 V1/V2/跨实例兼容。authprivacyhttp 包因该模式无匹配测试，不计入通过数量；未运行 HTTP/真机/Dart 验收。
- `go vet -mod=readonly ./internal/commentsnapshot ./cmd/commentsnapshotctl`、`go build -mod=readonly ./...` PASS。三份 Python ACL 夹具 AST 检查、gofmt 与 git diff --check PASS。未将 AST 解析称为实际进程 campaign 验收。

本轮只有测试 token 向量这一处失败修正后的单例复跑；未反复运行容量或性能套件，没有新 PG↔Redis 性能对照、实际30分钟、整机、时钟修复或部署。

## 结论与遗留

本地实现和必要定点检查已完成。正常分支已由实际 Redis 命令计数证明使用状态字节更新，原补偿与失败边界保持。复杂度收益限于省去该次 Publish 的整份 Lua 重构/SET 参数，完整账本扫描仍为 O(N)；未证明足以关闭端到端 P95 缺口。

原 steady 回复展开 P95 **+7.5716285574% FAIL** 保留。新候选性能为 **NOT_RUN / Redis启用前待可靠环境验证**；旧版本性能、30分钟及设备证据仅保留原版本/范围，不能提升为本候选重新通过。默认 PostgreSQL/readRedis=false，未合并、部署或启用 Redis。既有 CI 自动包含新增 package 测试；本地候选提交后的远端 CI 和独立审查另行核对。

完整私有日志、输入/最终源码哈希、补丁和通知回执位于 [D盘执行记录](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/post-pr-publish-state-implementation-sol-20261027/execution-evidence.json)。

## PR80 送审收尾

限定只读复核确认本实现符合已批准方案，未发现阻断；删除新增块后原 writer 逐字节一致。复核核对15个文件、158个产品源码文件及现有日志，没有重跑测试或压测。见[复核报告](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/post-pr-publish-state-review-astra-20261027/review-report.md)。

本轮按既有授权提交到 `zewbby/HnuHole` 的原分支及 [PR80](https://github.com/zewbby/HnuHole/pull/80)。最终 head、逐 workflow/job 结果和实际失败修复以 [PR Checks](https://github.com/zewbby/HnuHole/pull/80/checks) 及[送审回执](D:/HnuHole-task-storage/comment-snapshot-redis-20261024/post-pr-publish-state-delivery-sol-20261027/delivery-report.md)核对，旧 head 的 CI 不作为新候选通过。本轮不重复本机验收或性能压测；原性能 FAIL、新候选性能待验及默认 PG 保留，未合并、部署或启用 Redis。
