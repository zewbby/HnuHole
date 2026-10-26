# 评论分页快照迁移第 1 阶段基线与接口记录

工作项：COMMENT-SNAPSHOT-REDIS-01。更新时间：2026-10-24，Asia/Shanghai。

本阶段按 [执行计划](execution-plan.md) 和 [需求 V1.1](requirements-v1.1.md) 完成静态盘点、隔离工作区及接口接点固定。调度指定 GPT-6.1 Sol / high；不声称由本记录改变模型设置。没有实现快照存储、运行产品测试或进入第 2 阶段。

## 基线与依赖

| 项目 | 本轮确认 |
| --- | --- |
| 仓库 | `https://github.com/zewbby/HnuHole.git`；原始 worktree `E:/Hnuhole-env/source/HnuHole` 为旧 detached HEAD，不在其上开发。 |
| 已 fetch 的 main | `8ed8f2870b1724de2837ea40a6e3764c008780f7`，PR #72 文档回执。 |
| 本需求分支 | `codex/feat/comment-snapshot-redis`，从上述固定 SHA 建立。 |
| 本需求独立工作区 | `E:/Hnuhole-env/source/HnuHole-comment-snapshot-redis`。创建时干净，本阶段仅增加和更新文档。 |
| 评论区依赖 | [PR #71](https://github.com/zewbby/HnuHole/pull/71) 已合并，merge SHA `a715dc7e8b6a3b1395bc968274bce3865f63f21b`，已包含于本轮基线。 |
| 共享限流依赖 | 分支 `feat/shared-rate-limit-abuse-control`，工作区 `E:/Hnuhole-env/source/HnuHole-shared-rate-limit`，HEAD 同为 `8ed8f2870b1724de2837ea40a6e3764c008780f7`，功能代码尚为未提交差异。 |
| 限流 PR / CI | GitHub 按该 head、all 状态查询无 PR；机器记录 remoteCI=NOT_RUN、merged=false。该聊天正在推进设备验收及后续 PR/CI，不等同于已完成。 |
| 依赖复用边界 | 本轮只读取并记录候选文件 SHA256，没有复制限流未提交源码、运行其夹具或修改其工作区。 |

本轮 Git preflight、基线、候选文件 hash、完整旧表引用及输入文件 hash 见 [机器证据](stage-1-evidence.json)。候选 hash 只固定本次观察内容，不能代替未来正式提交或合并 SHA；限流正式交付后，第 3 阶段前重新核对并集成。

## 已合并评论区必须保留的行为

- `services/api/internal/comments/order.go:39` 定义 `relevant`、`recent`、`likes`。主评论首次请求允许 sort；带 cursor 的请求及回复请求不再传 sort（`community_comments_read.go:108`、`authprivacyhttp/comments_endpoints.go:269`）。不改变排序算法。
- 当前签名游标为 52 字节 canonical base64url：16 字节 snapshot UUID、4 字节 offset、32 字节签名；域分隔符为 `HNUHOLE/COMMENT-CURSOR/V1`（`community_comments_read.go:82`）。不能在本阶段擅自改签名或承诺新存储路由协议。
- `comment_views.dart:239` 起的本地发表展示、`:573` 起的成功回读、`:690` 起的列表读取和去重，以及按需回复队列逻辑必须保留。提交即显示和服务端确认的事实保持区分。
- 当前正常模式主评论和每层回复各持独立 cursor；`sort` 切换清空相应列表再发首页请求（`:1181` 起）。临时置顶、局部恢复等 V1.1 差异在后续客户端阶段实现。
- 草稿、结果未知、原命令重试、身份与账号隔离仍归原发布协议。本人发言记录 `ReadOwnComments` 使用独立的时间/ID 分页，不读 `c_comments.snapshots`，本期不将它扩展成 Redis 名单。
- 基线客户端 `CommentHttpFailure` 尚无限流分支新增的 Retry-After 字段；后续集成必须保留共享限流对评论草稿和错误分类的更新，不能用本分支旧文件覆盖。

## 旧快照表入口完整清单

基线业务代码共五处直接访问，均在 `services/api/internal/authprivacy/community_comments_read.go`：

| 行号 | 入口 | 后续迁移要求 |
| --- | --- | --- |
| 149 | 后续主评论或回复分页 SELECT | 按存储来源读取，校验账号/帖子/根评论/到期，保留越界检查。 |
| 199 | 首次读取前 DELETE 过期快照 | Redis 正常路径不得继续调用旧表全局清理。 |
| 203 | 首次读取账号 count | 替换为跨实例原子额度；不能继续用旧表作为 Redis 快照配额依据。 |
| 209 | INSERT 名单，固定 5 分钟 | 改为存储边界创建与 30 分钟有效期；保留 PostgreSQL 兼容实现。 |
| 371 | LocateComment 再次 SELECT 名单 | 与列表使用同一存储边界，不能留下定位查询旧表的遗漏。 |

其他直接引用为 `services/api/migrations/0016_comments.sql:74/82` 的建表和过期索引、`infra/postgres/grant-comments.sql:4/7` 的权限，共九处直接表名引用。间接引用另包括 `community_comments_schema.go:44/67/73` 的 schema/权限校验及 `authlab/privacy-role-audit.sql:111/112` 的白名单。本期保留旧表用于兼容和明确回退，不删除历史迁移或放宽权限。

启动 schema 检查是否按存储模式细分，交第 2 阶段设计；不能以禁用整个评论 schema/Gate 检查解决迁移。过渡结束后的验收须证明业务快照读取、写入、配额和过期清理均不再调用旧表。

## 接口和公共文件归属

本阶段固定“接在哪、谁负责、必须提供什么”，不实现或提前决定第 2 阶段的 Redis 原子协议、游标版本及补偿算法。

| 接点 | 固定职责与边界 |
| --- | --- |
| `authprivacyruntime/config.go` 的 CommentsConfig | 快照设置归评论配置，包含存储开关/兼容读取、专用 Redis 连接信息、池与调用期限、固定 1800 秒、ID 上限、账号额度、单份字节和模块预算。独立于 sharedRateLimit.Policy；字段签名在第 2 阶段设计中确定。 |
| `authprivacyruntime/server.go` 的评论装配 | 在现有 `community.WithComments` 附近注入快照实现；连接创建与关闭遵守 runtime 生命周期。公共连接工厂/依赖和部署模板由共享限流任务统一管理，快照接线和预算由本需求负责。 |
| `authprivacy/community_comments.go` 的 CommentConfig/commentServices | 存放快照存储接点，业务仍经 `withCommentSession`、`withPostSession` 完成 Gate/账号/事务校验。存储 API 的最终签名与跨存储提交顺序交第 2 阶段。 |
| `community_comments_read.go` | 主评论、回复、定位共用存储边界；只有有序 ID 和归属/到期/必要版本信息进入 Redis。 |
| `authprivacyhttp/comments_endpoints.go` 与 `packages/openapi/comment-api.yaml` | 保留现有主评论、回复、定位路径和分页数据字段；sort/cursor 互斥、预览 5 条、limit 1–50 不变。新增容量与存储错误同步实现、契约和客户端。 |
| 客户端 `comment_http.dart` / `comment_runtime.dart` / `comment_views.dart` | 沿用严格 error code/message/requestId 结构与 no-store；集成限流 Retry-After 后再接快照错误。区分 Gate 故障、限流故障、快照故障和无效游标，不将快照错误升级为整账号授权失效。 |

### Redis 复用约束

- 依赖版本复用限流候选的 `github.com/redis/go-redis/v9 v9.7.3`；本阶段 main 尚无该依赖，不单独写入 go.mod/go.sum。
- 复用有界池、短超时、ContextTimeoutEnabled、禁止隐式写重试的模式；快照拥有独立 client/pool 与统一的一次短重试预算，不能直接调用私有的限流 Controller.client。
- 快照 namespace 必须同时标明环境、用途和版本，并与限流完整 key 前缀及其运行 ACL 不交叠；后续统一公共配置。快照运行身份只能操作快照前缀，不能清理限流键或执行 FLUSH/CONFIG。所需最小 Redis 命令由第 2 阶段的实际存储协议确定，不能先给全命令权限。
- C/V 隔离、单 Redis 7 primary 和 noeviction 保留。256 MiB 是开发示例，不是可用快照预算；默认账号额度、字节预算与限流预留须经后续容量测试固定。
- 当前公共交付提供 `infra/ratelimit/` 配置及 runbook，`infra/docker-compose.yml` 未接 Redis。如实际环境使用 Compose，由公共负责人统一补齐，不在快照分支重复建设。
- 限流 verified-db 降级、持久准入协调和恢复屏障不可复用为快照存储语义；不触碰限流 policy/hash/generation。快照故障仍遵守不静默回 PostgreSQL、不套用旧偏移重建。

## 后续验收入口和新设备约束

- 第 2 阶段：一致性设计、游标兼容与存储开关、原子配额/字节预算、写入未知和 SQL 失败补偿，不进入实现。
- 第 3/4 阶段前：必须重新核对共享限流正式提交/合并结果与上述候选 hash 的差异；无正式交付时，不把候选代码当成已合并依赖。
- 现有后端入口为 `community_comments_test.go`、`community_comments_business_test.go`、`community_comments_migration_test.go`、HTTP 评论测试、`authlab/run-comment-text-isolated.sh` 及 comments workflows；客户端为 comment views/controller/journal/http 相关测试。共享限流夹具可复用工具模式，不转移既有测试结论。
- 第 5 阶段仍需真实 Redis、一次性 SQL、两个独立 API 进程、10 页带回复容量场景及 P95 对照，不在本阶段运行。
- 调度转达的用户新要求：后续若现有连接允许独立控制手机，可直接完成真机；否则记为“真机验收待用户于 2026-10-25 验收”，继续其他工作，不要求用户现在配合，不把未验写成通过。本阶段不操作手机。

## 本阶段完成证据

| 项目 | 状态 |
| --- | --- |
| 最新 main fetch、SHA 和隔离分支核对 | PASS |
| 评论区 PR #71 合并事实及当前行为核对 | PASS |
| 共享限流提交/PR/CI/合并状态、候选 hash 核对 | PASS；事实为尚未提交合并，后续实现依赖待集成。 |
| 连接/配置/ACL/超时接口接点与公共归属 | PASS；固定边界，最终协议由第 2 阶段设计。 |
| 旧表五处业务、四处迁移/权限、五处 schema/审计引用 | PASS；全量列表见机器证据。 |
| 文档链接、UTF-8、静态源码行号和产品文件未改动检查 | 结果见 stage-1-validation.json。 |
| 新功能测试、真机、远端 CI、提交/推送/合并/发布 | NOT_RUN；本阶段无此实施范围。 |

只结束第 1 阶段。第 2 阶段等待调度指定模型与推理强度，不自动开展。
