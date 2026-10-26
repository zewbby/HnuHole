# 第 3 阶段：服务端迁移与正式依赖集成

日期：2026-10-25。任务 `COMMENT-SNAPSHOT-REDIS-01`，调度指定 GPT-6.1 Sol / high。本阶段完成服务端实现和限定真实验收，未开始第 4 阶段客户端；未提交、推送、创建 PR、合并本需求或发布。

## 正式基线和差异保护

本需求最初从 `8ed8f2870b1724de2837ea40a6e3764c008780f7` 建立独立分支 `codex/feat/comment-snapshot-redis`。本轮 fetch 后验证共享限流 PR [#73](https://github.com/zewbby/HnuHole/pull/73) 的 Squash 提交 `c05198155543b8d1a259dc41fdeb860126dee7d0` 属于 `origin/main`，将本分支 fast-forward 到该提交；没有创建集成 merge commit，也没有复制候选工作区的未提交源码。

集成前将全部已修改及未跟踪文件、binary diff 和暂存差异备份到本任务外层目录 `comment-snapshot-redis-20261024/pre-main-integration-20261025/`。原 working.patch SHA-256 为 `99ff8018a4d233bb003eb48db679fc78eeef025805119daa100ed48a8e78dcd4`。撤销该份自己的 tracked diff 后 fast-forward，再三方重放。文档、go.sum、runtime import、HTTP 错误分类冲突逐项合并，保留共享限流装配、`SHARED_RATE_UNAVAILABLE`、86400 秒 Retry-After 上限及全部既有客户端成果；最终暂存区为空。本需求差异仍为可审查的本地工作区文件。

## 已实现行为

- `internal/commentsnapshot`：不可变 ID 二进制载荷、MAC 校验、带 backend/epoch/sort 的 V2 游标、固定 1800 秒到期；单份最多 10000 ID，不因翻页续期。正常 Load 只读 control 和目标 data，不读取全局名录。
- Prepare 原子保守预留账号额度及模块字节预算，随后记录 watermark 并写 data；SQL/Gate 成功提交后 Publish，最后才签发游标。SQL 失败执行独立有界补偿；未知写入不自动重发。pending 租约 30 秒，后台间隔 10 秒有界回收，ABORTING 围栏阻止迟到 Publish 复活。
- `community_comment_snapshots.go`：主评论、回复和定位统一路由；V1 继续读取旧 PG，V2 按签名来源读取。显式 PG 新建使用 30 分钟 V2；双读时在既有账号锁内合计有效 PG 和 Redis 预留。关闭 readPostgres 后，列表、额度和定位不再访问旧快照表。
- 每次读取仍实时检查会话、Gate、帖子、根评论及内容可见性；名单冻结，计数及内容实时。最多扫描三个全不可见段，按原 ID 位置推进，允许空页带 nextCursor。回复预览最多五条，expanded 沿用原协议。
- 可选 `X-Comment-Snapshot-Request` 为 canonical 16 字节非零 nonce：同账号同范围重试复用 active 快照及原期限；跨帖子/楼层/排序复用拒绝，不能与 cursor 同传。PG 兼容来源不提供跨提交的 nonce 恢复。
- 错误区分：400 CURSOR_INVALID/MALFORMED_REQUEST；422 COMMENT_SNAPSHOT_TOO_LARGE；429 RATE_LIMITED；503 COMMENT_SNAPSHOT_CAPACITY/UNAVAILABLE/INTEGRITY。未复用限流故障码表示快照故障，未静默回退 PG。
- Runtime 新增 `comments.snapshots`，校验运行额度、环境 namespace、runtime ACL 用户、秘密文件，拒绝与共享限流配置同一 Redis 地址。快照使用独立进程；部署者仍须确认不同地址实际没有指向同一实例。连接池独立，go-redis 禁止隐式重试。
- `commentsnapshotctl` 使用同一完整私有 community runtime 配置及评论用途密钥。`--check` 使用 runtime ACL；全新 namespace 初始化额外要求独立 operator 用户/秘密文件，API 不自动初始化或重置。现有 namespace 拒绝再次初始化。
- 输出创建预留、成功读取、失效读取、额度拒绝、Redis 调用错误、累计操作耗时，以及最近成功采样的预留字节/独立实例 used_memory。指标不含账号、正文、快照 ID 或 nonce。容量配置是待阶段 5 实测的候选值。

源码入口：`services/api/internal/commentsnapshot/`、`internal/authprivacy/community_comment_snapshots.go`、`authprivacyruntime/config.go` / `server.go`、`cmd/commentsnapshotctl/`。配置和 Redis 模板位于 `infra/commentsnapshot/`；接口更新位于 `packages/openapi/comment-api.yaml`。新产品 CI 为 `.github/workflows/comment-snapshot.yml`。

## 最终验证与边界

测试环境为本任务独立 WSL Linux 镜像，Go 1.22.2、PostgreSQL 16、Redis 7.0.15、Goose v3.22.1、Pillow 12.3.0。Redis fixture 创建子进程并核对其 process_id 后才进行故障注入；SQL runner 创建独占私有 socket 的一次性数据库。没有清共享 Redis、既有数据库或日常手机数据。

| 检查 | 本轮结果 | 证明范围 |
| --- | --- | --- |
| `sh services/api/authlab/run-comment-snapshot-isolated.sh` | 23 顶层 PASS、0 FAIL、2 SKIP | 7 store 检查（1 codec + 6 真实 Redis）、1 CLI 参数 guard、10 authprivacy（含 2 新快照真实 SQL）、5 HTTP 检查（含新增真实 TLS/Redis/SQL）；不相加历史轮次 |
| `sh services/api/authlab/run-shared-rate-limit-isolated.sh` | 39 顶层 PASS、0 FAIL、1 SKIP | 正式共享限流的实际 Redis/SQL/TLS/上传/CLI 回归；设备长驻夹具未请求 |
| `go test -mod=readonly ./...` | PASS | 全后端宿主测试；无 DSN 的既有数据库/设备 fixture 会明确跳过，不作为 SQL 证据 |
| `go build -mod=readonly ./...` / `go vet -mod=readonly ./...` | PASS | 最终后端完整编译及 vet |
| 完整 OpenAPI + 评论/社区/DM 契约 | PASS | 12 份规范及相关完整 checker；静态契约不等于设备结果 |

真实 Redis 覆盖固定 TTL/nonce、两个 Store 实例 16 并发的硬额度、ACL 隔离/禁止 runtime CONFIG 和 operator SCAN、部分脚本写入后保守记账及补偿、实际 maxmemory OOM 下只读继续、data 丢失与 ledger 丢失区分、ABORTING 和实际 31 秒 pending 回收。

真实 SQL 覆盖 V1/V2 PG/Redis 路由、混合配额和等待时间、回复预览/展开、跨账号/帖子/类型拒绝、三段不可见扫描、定位、重建服务实例读取同一快照、将旧表暂时改名后 Redis 路径仍工作、最小 runtime SQL 角色。延迟约束 trigger 在 SQL COMMIT 注入失败，确认不返回结果、不遗留新增预留，同时原 Safety Gate 按设计冻结；测试未绕开或手工放松这个冻结。

新增 HTTPS 测试通过真实 TLS handler、双 SQL 和 Redis，验证 nonce 实际传递、游标续读、nonce+cursor 的 400，以及停止本测试 Redis 子进程后的快照 503；未回退 PG。跨实例证据目前为同进程独立 Store/服务装配，不冒充阶段 5 要求的两个独立 API 命令进程。

两项评论跳过是 `TestCommentBusinessDevicePostgres` 和 `TestCommentBusinessDartLivePostgres`；共享限流跳过为 `TestSharedRateDevicePostgres`。第 4 阶段客户端及 Dart 联调尚未开展；真机验收待用户于 2026-10-25 验收（后续能独立操控则自行完成）。本任务未跑远端 CI、容量/P95、实际 30 分钟连续阅读、两个 API 进程或生产滚动发布，留第 5–7 阶段；不提升原模块总验收裁决。

## 失败历史和证据

保留 `snapshot-sql-r1.log`：SQL COMMIT 故障正确触发 Gate 冻结后，测试继续业务请求而失败；调整为最后测试并断言冻结，没有改 Gate。保留 `snapshot-final-r1.log`：图片验证器所在源码父目录不符合既有私有执行要求，图片回归失败；runner 改为复制同一验证器到本任务 0700 临时目录、0600 脚本并生成固定图片夹具，最终 r2 全部适用项通过。早期宿主镜像缺 protocol vectors 和一次 ACL 测试 API 名称编译失败也已修正，不能用此前不完整运行替代最终结果。

最终日志：`/home/hnuhole/comment-snapshot-redis-20261024-8ed8f28/logs/`；Windows 脱敏副本：`C:/Users/24237/Documents/ChatGPT/Hnuhole/comment-snapshot-redis-20261024/stage-3-evidence/`。机器记录见 [stage-3-evidence.json](stage-3-evidence.json)，源码/日志 hash 与静态核验见 [stage-3-validation.json](stage-3-validation.json)。重现入口在仓库内，绝对机器路径只用于定位本次证据。

下一步仅等待第 4 阶段调度；客户端应按本阶段固定错误码、nonce 和局部恢复契约继续。
