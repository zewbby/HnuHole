# 评论与回复：真实后端文字链路

本轮结果为 **BACKEND_TEXT_SCOPED_PASS**，不代表完整评论功能完成。分支 `codex/feat/comments-backend-text`，[Draft PR #19](https://github.com/zewbby/HnuHole/pull/19)，堆叠于已交付核心的[PR #17](https://github.com/zewbby/HnuHole/pull/17)。后端被测实现为 `07911ab13fa034e186a9de79864004a4bbd3d3e4`；机器记录见[验证证据](comments-backend-text-verification-20261018.json)。

## 实际基线与范围

本轮开始时 main 仅0014，先完成独立组件。交付前真实 main 已更新到 `1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`（PR #18，治理0015），因此正常整合到核心基线 `767b0a3` 再整合本分支，保留双方功能及台账。没有合入治理未完成分支或复制未提交代码。最终交付使用正式0016；早期未编号组件夹具只作为过程历史，已移除，不能拿旧夹具结果替代正式迁移链。

Go/Dart原核心及黄金向量继承，不重写也不重跑其完整宿主验收。本轮无 Flutter 页面/路由、原生日志/进程重启、图片、系统通知/举报审核适配、真机、Passkey 或 iOS 增量。PR相对base没有客户端文件差异。

## 真实 HTTP 能力

所有路由使用当前 C Bearer 会话、TLS和最终Gate事务，响应no-store并附可信服务器时间及会话期限。图片字段必须为null；未知字段、重复JSON键、非法Unicode、非规范UUID、空字符串充当nullable UUID、歧义头或查询均拒绝。

| 路由 | 已实现行为 |
| --- | --- |
| `PUT /api/v1/comment-commands/{commandId}` | CREATE文字主评论/明确目标回复；RETRY仅原任务匹配FAILED版本、原身份/原目标；ABANDON仅匹配FAILED版本并擦除未发布文字。受理202，其他权威回执200。 |
| `GET /api/v1/comment-commands/{commandId}` | 本账号原始回执；受理后即使已发表仍返回原ACCEPTED；未观察到回执返回UNKNOWN_NOT_OBSERVED，不能推断失败。 |
| `POST /api/v1/comment-commands/{commandId}/seal` | 原账号/键/操作/摘要串行封口；已存在则回放，未受理则永久NOT_ACCEPTED，迟到原请求不会产生任务。 |
| `GET /api/v1/me/comment-tasks/{taskId}` | 本账号当前权威状态、原身份/帖/楼/目标、版本、允许动作及保留内容；其他账号404。 |
| `GET /api/v1/posts/{postId}/comments` | 当前可读帖的文字主评论与总数量，既有核心排序和冻结分页；公开DTO无内部账号/身份/任务ID。 |
| `GET /api/v1/posts/{postId}/comments/{rootCommentId}/replies` | 明确楼/目标关系，默认前五，expanded继续其余；检查路径帖与实际楼一致。 |

线上的文本子集规范为[comment-text-component.yaml](../../packages/openapi/comment-text-component.yaml)，引用原冻结DTO/回执/摘要契约。原完整 `comment-api.yaml` 保留为首阶段设计快照；未列出的设计接口不意味着可调用。点赞/删除/定位接口未实现，当前likeCount=0/likedByMe=false，排序仍调用原核心；不是完成点赞功能的声明。

## 事务、数据库与授权

正式迁移为 `0016_comments.sql`，上游为真实 `0015_reports_moderation.sql`。最小授权见 `grant-comments.sql`；`grant-community.sql` 只补评论功能关闭时仍需的生命周期读取/擦除。已有运行时用途密钥查重、受控文件权限和最终Gate保持不变。显式配置与启动入口见[数据库说明](../../services/api/comment-schema/README.md)。

`c_comments` 保存任务、尝试、命令回执、用途密钥承诺和短期顺序快照；原始命令键只存账号范围HMAC。账号先锁，再锁帖子；调用既有状态机与固定身份规则。任务、受理回执、首次参与者绑定同一事务提交，SQL延迟约束阻止单纯选择身份产生绑定。数据库约束保证账号/身份归属、同帖同楼目标、递增重试版本和每任务至多一次发表；永久绑定/回执及已终结尝试不可重写。权限/内容业务拒绝留下稳定REJECTED回执且无新任务/绑定；基础设施错误回滚，结果仍待原键核对。

沿用既有stop generation，禁言/封禁/申请注销停止待发送任务；到期不会复活旧尝试。身份删除隐藏本人恢复并擦除未发布文字，公开事实使用既有安全标签。正式闭号在评论接口关闭及受限角色下也能清理。审核下架和帖子删除禁止读取/新发送，待发送尝试明确失败为POST_UNAVAILABLE。没有增加通知中心或失败通知provider。

读取快照只存ID、账号/帖/楼范围和5分钟期限，不存正文；每账号最多128活跃任务/快照、每分钟120新命令，单快照超过10000条明确拒绝。新内容等待新快照；不可用内容不通过游标恢复访问。

## 本轮实际验证

环境为本任务私有 WSL Linux 文件、PG16 Unix socket端口55463、Go1.22.2、Goose3.22.1；工具/缓存/日志位于本任务runtime目录。没有连接未知/生产库、修改其他session或使用手机。实验PG和TLS服务退出已清理，日志只保留测试名/结果；合成密码、令牌、正文或查询参数不进入证据。

1. `bash services/api/authlab/run-comment-text-isolated.sh`：**PASS**。12个顶层检查加Goose2个子项，零FAIL/SKIP；其中真实数据库检查含空库0001–0016、0014→真实0015→0016、版本0–16连续且Down失败后仍16；并发8次原键只一尝试、冲突和越权、固定身份、明确多层目标、冻结分页/范围隔离、UNKNOWN与seal、失败/原身份重试/放弃擦除、冻结Gate、审核下架、删身份、关闭功能后的受限闭号清理。真实TLS HTTP覆盖文字/回复/任务/原回执/重试/放弃/封口/严格边界。另仅重开3个受影响的旧绑定/治理清理检查。
2. `go test -race -mod=readonly ./internal/comments ./internal/authprivacyhttp ./internal/authprivacyruntime -run '^(TestCommentTextPersistenceCheckpoint|TestCommentTextExplicitRuntimeConfiguration|TestCommentTextNullableBoundary|TestStrictJSONRejectsAmbiguousInputs|TestStrictObjectFieldsAndTypes|TestModerationAccessHTTPBoundary)$' -count=1 -v`：**PASS**。6个顶层检查，旧认证解析仍拒绝null；没有运行Dart/Flutter全量测试。
3. `go build -mod=readonly ./cmd/authdev`（产物写本任务runtime）及受影响4个Go包的 `go vet -mod=readonly`：**PASS**。
4. 固定Python3.12/PyYAML6.0.1/openapi-spec-validator0.9.0运行 `tools/check-comment-text-contract.py`：**PASS**，只校验文字子集及其原契约引用。

受限运行角色实际执行接受/发布/读取/生命周期，不能删除永久回执、改身份或stop generation、TRUNCATE或DDL；原schema guards阻止已发表回退。通用隐私role-audit白名单同步限定新表/列，未在本轮重跑无关的全套双集群/生产审计，也不据此宣称全项目通过。既有图片、认证、无障碍成果随main整合保留，原测试版本不被本轮局部结果覆盖。

## 失败历史与修复

首个产品head `718d5f4` 的新增文字CI通过，但继承的图片SQL CI在 `TestPostImagesRestrictedRuntimePostgres` 失败：绑定延迟约束在原帖作者分支的同一SQL内仍检查了评论回执表权限。`07911ab` 改为PL/pgSQL提前返回，保留原发帖最小授权，未扩大回执读取。新增“评论接口关闭时受限角色实际发帖”回归并重跑本轮真实SQL/Goose/TLS HTTP，全部通过；最终远端图片检查以PR head结果为准。此失败没有被计入PASS或隐藏。收尾日期为2026-10-19，工作项和报告文件保留20261018编号。

## 未完成与审查安排

治理迁移依赖已解除。#19仍依赖核心#17先合入，再调整base；独立成员审查及最终head远端CI以PR实况为准，不伪造批准或使用合并绕过。本session没有合并/发布授权，因此保持draft，未部署。

完整B07仍BLOCKED，COMMENT-FAIL-ENTRY-01仍NOT_RUN_NOT_CONNECTED。下一轮建议先做文字客户端/原生任务日志与实际恢复接线；点赞/定位/本人删除、图片、通知provider及设备另行授权推进，本轮不自动进入。
