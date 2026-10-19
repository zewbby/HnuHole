# 评论举报审核完整闭环

2026-10-19，Asia/Shanghai。分支 `codex/feat/comment-report-moderation`，从当时最新 main `41ed0c5` 创建，正常整合 #17、完整评论 #19（`2da7cdf`）及其交付文档 #21（main `7b2dd16`）。没有合入未完成功能分支或复制其他 session 工作区。

实现完成，新增限定验证 **PASS**，独立只读审查无阻断；合并状态见 [PR #22](https://github.com/zewbby/HnuHole/pull/22)（开放时待合并，merged 时本任务交付关闭）。未部署／发布。

本轮一次交付真实主评论／回复（文字及单图）举报→原提交结果核对→电脑网页审核处置→本人系统通知与单条已读→必要申诉及独立复核。复用 #18 案件、权限、处罚、审计和通知，复用 #19 评论实体及原失败任务，不另造 provider 或发送系统。

- 产品提交 `dd436d6`，文档整合 `e84807c`；实际输入与命令见[限定报告](../design/comment-report-validation-20261019.md)及[机器记录](../design/comment-report-verification-20261019.json)。沿用旧证据，仅补新增评论链及受影响部分；6项新SQL/race、1项真实Dart HTTPS/网页闭环、45项Flutter、analyze0/bundle、Go build/vet、管理12项及10份API校验通过。
- 数据库迁移 [0018](../../services/api/migrations/0018_comment_reports.sql) 接在实际0016/0017后，不覆盖已合入迁移；runtime重跑对应权限脚本，缺失新钩子／列／处置权限拒绝启动；Down拒绝。
- [通知与举报契约](../design/report-notification-contract.md) 固定 `postId/commentId`、原举报键、身份隔离、通知路由／去重／已读及评论原任务动作边界。评论模块真实失败、重试、放弃和通知移除已在 #19，当前直接复用。
- 覆盖跨帖伪造、角色越权、不同评论同文不合案、同目标跨原因合案、并发唯一处罚、举报人/其他面具隐私、单图及旧游标读取、回复/整楼下架、作者删除、父帖状态和独立恢复。
- 独立 `auth_integration` 只读安全复核已完成，不冒充GitHub成员批准。最终head CI、main包含与合并SHA由本任务PR回执固定；不为补写相同完成状态另开文档PR。

接续入口：[HANDOFF](../design/HANDOFF.md)、[progress](../design/progress.md)、[B08/B11交接](../design/module-acceptance-handoff.md)。本范围交付合并即停止；私信、推送、完整消息中心、新处罚政策、Passkey、iOS、生产部署和额外手机矩阵未展开。
