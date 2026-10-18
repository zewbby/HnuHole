# 文字评论与回复后端增量

- 更新时间：2026-10-19。
- 分支：`codex/feat/comments-backend-text`；[Draft PR #19](https://github.com/zewbby/HnuHole/pull/19)，base 为[核心 PR #17](https://github.com/zewbby/HnuHole/pull/17)。本轮 diff 没有 Dart、Flutter 页面或原生代码。
- 已正常整合 main `1b78f42`（治理 PR #18），通过 #17 基线 `767b0a3` 继承；后端被测实现 `07911ab`。原核心任务范围见[评论与回复](feat-comments-replies.md)。
- 结果：**BACKEND_TEXT_SCOPED_PASS**，未合并、未发布；完整 B07 仍 BLOCKED，实际系统通知 provider 未接入。

本轮实现真实 PostgreSQL 任务、不可变命令回执/封口、固定帖内身份和回复关系，真实 C HTTPS 接口与后台发布。接受、重试、放弃、失败/发表调用已有 Go 规则，在最终 Gate/会话/账号事务内检查归属及资源。尊重治理下架与既有禁言/封禁/注销；功能关闭时仍有最小生命周期清理授权。文字没有长期草稿。

正式 `0016_comments.sql` 紧随已合入的真实0015。Goose空库0001–0016、0014→0015→0016、连续版本账和拒绝Down均通过。本任务私有PG16、受限运行角色、实际TLS HTTP、并发/越权/结果未知/重试放弃/冻结及受影响共享回归通过，命令和范围见[报告](../design/comments-backend-text-report-20261018.md)及[机器记录](../design/comments-backend-text-verification-20261018.json)。产品CI为 `Comments backend text`，远端最终head结果以PR检查为准。

合并顺序：#17 → #19；#17合入后须重新核对base，避免核心重复差异。独立成员审查待完成，没有合并/发布授权。本轮停止于可审查后端增量；下一轮建议先补文字客户端接线和原生任务日志，另行安排点赞/定位/本人删除、图片与通知，不自动执行。Passkey、iOS及设备继续延期。
