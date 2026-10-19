# 评论举报审核闭环限定验收（2026-10-19）

`codex/feat/comment-report-moderation` 的本任务范围为 **COMMENT_REPORT_CLOSED_LOOP_SCOPED_PASS**。产品提交 `dd436d66185d1ce0ac871c3d55bc10511364843a`，测试夹具修复 `ec6672f35d4124e495299d133eeca15178c19d3b`；正常整合 main `7b2dd1634c3ffb3835543a8a49c9d22cdbcc2f52` 后产品输入未变；完整指纹、逐项结果和未执行项见[机器记录](comment-report-verification-20261019.json)。合并状态与最终提交以[任务详情](../branches/feat-comment-report-moderation.md)指向的 PR 实时回执为准，未发布。

## 实际交付

真实主评论及回复的“举报”入口携带父 `postId` 和具体 `commentId`，文字及单张原图在最终授权事务复制为不可变证据。复用原请求键／封口／retryToken、跨原因合案、版本竞争、角色、既定处罚、审计、账号与身份通知和三轮必要申诉。不同评论即使同文也不合并，帖子原协议指纹保持兼容。

处置账号取评论实际作者，不处罚父帖作者、不下架父帖。回复下架只隐藏自己，主评论下架阻断整楼读取；列表、旧快照、本人历史、定位、原图、点赞和新回复均执行相同可见性边界。作者仍可删除被下架内容；根评论删除逐条结束未完成回复案件，删帖沿既有钩子终结评论案件。撤销仅修正对应处置，不恢复作者删除，不绕过独立父帖或根评论限制。证据及审计保留原治理规则。

电脑同源 HTTPS `/admin` 显示具体评论文字与图片，复用审核员／管理员和原处理人回避。管理 DTO 不暴露举报人、邮箱、内部账号映射或其他面具。举报通知路由先核对原 `requestId`，再读取权威 `postId/commentId`，App 打开评论原定位；不可访问目标沿既有统一不可读提示。处罚与申诉沿原本人资源路由。

## 新增验证

| 检查 | 实际结果与证明范围 |
| --- | --- |
| 新评论举报真实 PostgreSQL16 / Go1.22 race | 6 PASS / 0 FAIL / 0 SKIP：归属／跨帖／跨身份／越权、重复、并发唯一处罚、通知单条已读与隐私、单图、旧游标、申诉、作者/根评论/帖子删除、独立恢复、最小 runtime 权限及缺失拒绝 |
| 真实 Dart → Go HTTPS → SQL → 网页 Edge | 1 PASS：已发布单图回复举报、原结果核对、实际网页登录/证据/领取/MUTE3/审计、本人通知/已读、原申诉核对及另一管理员复核、回复和原图从404恢复200，父帖和根评论持续可读 |
| 受影响 Flutter 文件 | `flutter test --no-pub test/governance_test.dart test/comment_views_test.dart`，45 PASS；包含真实行入口与准确评论路由、原提交目标防串写；analyze 0，`flutter build bundle --no-pub` PASS |
| Go / API / 管理页 | Linux源码归档 `go build -mod=readonly ./...`、`go vet -mod=readonly ./...` PASS；新增报告模型单位1 PASS；完整10份 OpenAPI validator PASS；Node语法及管理12项PASS |
| 迁移 | 真实 Goose v3.22.1 从0017升级0018、历史账号保留、账本连续0..18、Down拒绝且仍18；新业务夹具从空库装正式0001..0018。旧评论迁移测试固定up-to17，保持原历史证明范围 |
| 独立审查 | `auth_integration` 只读独立复核产品 `dd436d6` / 整合 `e84807c`，无阻断／无未关闭finding；agent审查不冒充GitHub成员批准 |

一次性库入口：在 `services/api` 执行 `MODERATION_TEST_PATTERN='^(TestCommentReport|TestRealHTTPSCommentReport)' sh authlab/run-moderation-isolated.sh`，配置自有 PGPORT、Goose、媒体验证器和 Dart/browser probe。Go测试名及环境要求在源码中固定。该 runner 拒绝外部 DSN／root，使用专属角色、私有 socket／一次性库，结束清理库、进程及密钥。实际本地分轮只执行新增项，首轮两项测试断言使用了不同于既有协议的错误码及一个旧列名，修正断言后仅补验失败项；非产品缺陷，不隐藏失败历史。

CI 首次还发现两处历史“治理前结构”夹具只删除治理 schema、留下0018列，触发正确的半迁移拒绝。提交 `ec6672f35d4124e495299d133eeca15178c19d3b` 只修夹具：先断言残留0018必须拒绝，再删测试列并验证旧结构兼容。两项受影响真实PG/race用例（含通用启动8个子项）定向PASS，独立增量复核无阻断；产品checker、授权、迁移及业务代码未变。原CI失败回执保留在机器记录，最终CI由PR实时head核对。

随后隔离恢复CI的审计清单仍沿旧矩阵，未列出0018的 `moderation_hidden` 与两个触发器。提交 `21b1704deb93c2c24d7557530a3b39093f32fa40` 仅补这1列/2函数的显式白名单，实际运行权限不变；真实SQL审计及case目标/root绑定不可变负向检查已定向PASS。对应失败记录保留，完整恢复CI仍按最终head核验；本轮没有部署/发布。指纹范围新增 `infra/prerelease/`，覆盖本次审计输入。

## 沿用与边界

沿用 [PR #18](https://github.com/zewbby/HnuHole/pull/18) 的[帖子治理证据](report-moderation-verification.json)和 [PR #19](https://github.com/zewbby/HnuHole/pull/19) 的[真实评论/失败通知证据](comments-connected-verification-20261019.json)。本轮未重做认证、处罚政策、原生 journal 或失败 provider。仅因新下架边界影响待发布回复，定向验已受理原任务变为 `COMMENT_TARGET_DELETED`、已有 SERVER 通知、禁止原目标重试与放弃后移除。

没有手机／iOS／Passkey／生产操作。App 改动仅为 Dart 举报入口和路由；现有组件测试、目标 bundle 与实际 HTTPS/网页验证用于该新增范围，不冒充原生设备验收。完整 B08／B11 仍为 PARTIAL（完整互动收件箱、私信证据、推送及生产保留政策等不在本任务），本任务评论举报业务没有待接 provider 或待开发页面。合并交付后结束，不自动寻找新功能。
