# 海南大学树洞

面向海南大学校内人员的封闭树洞社区，用于吐槽、互助、找搭子、发表想法和分享生活。致力于打造一款匿名程度尽可能高的匿名论坛，保护在校师生的个人信息。

当前已从产品设计阶段进入工程方案阶段，首版面向 iOS 与 Android。工程基线已确定为 Flutter/Dart 移动端、Go 服务端和模块化单体后端；仓库采用 monorepo，Go HTTP、PostgreSQL、REST/OpenAPI、服务端会话、移动端本地存储、CI/测试与部署基线已记录，具体云厂商、推送供应商和发布流程仍在后续决策中。

## 新会话接续

继续本项目讨论时先读[接续说明](docs/design/HANDOFF.md)，再按其中索引读取当前模块；不要从历史对话猜测最新规则。

## 设计入口

[产品设计目录](docs/design/README.md)是当前规则的统一入口，按模块维护：

- [账号](docs/design/modules/accounts.md) · [帖内身份](docs/design/modules/identity.md)
- [入口与导航](docs/design/modules/navigation.md) · [标签与屏蔽](docs/design/modules/tags.md)
- [新建帖子](docs/design/modules/post-composer.md) · [帖子详情](docs/design/modules/post-detail.md) · [评论与回复](docs/design/modules/comments.md)
- [消息中心](docs/design/modules/messages.md) · [私信与会话](docs/design/modules/messaging.md)
- [个人内容与设置](docs/design/modules/personal.md) · [内容管理](docs/design/modules/moderation.md)

当前规则只修改所属模块，本页不重复维护规则清单。

## 图稿与讨论记录

- [登录注册流程 UI 定稿 · 2026-10-21](docs/design/auth-flow-final/README.md)：欢迎页、用户名／邮箱原位切换、注册与恢复统一视觉基准，含交互稿与截图。
- [帖子详情图稿档案](docs/design/post-detail-dark-final.md)
- [回复输入 PNG](UI产品图/回复输入状态.png)
- [消息首页正常状态 v1 · 已确认](UI产品图/消息首页-正常状态-v1.png)
- [身份弹框 v3 PNG · 旧稿](UI产品图/首次发送-身份选择-v3.png)
- [历史讨论目录](docs/discussions/README.md)

按用户要求优先交付 PNG，设计图的确认范围在各模块内说明。

## 分支一览

| 分支 | 一句话说明 | 进度详情 |
| --- | --- | --- |
| `main` | 汇集已经合并的项目实现与文档。 | [详情](docs/branches/main.md) |
| `feat/login-home-recommended` | 登录直达首页，启动默认推荐、返回保留所选通道；2122测试包与单机指定验收通过，交付及合并状态见 [PR #40](https://github.com/zewbby/HnuHole/pull/40)。 | [任务详情](docs/branches/feat-login-home-recommended.md) |
| `feat/auth-entry-flow` | 将登录注册定稿接入真实 App，邮箱登录明确待接入；分支交付检查中，未正式发布。 | [任务详情](docs/branches/feat-auth-entry-flow.md) |
| `docs/auth-flow-final` | 归档用户确认的登录注册流程 UI 定稿与原位切换交互稿；PR #38已合入main，App 接入见 feat/auth-entry-flow。 | [任务详情](docs/branches/docs-auth-flow-final.md) |
| `codex/fix/comment-failure-reconcile` | 修复原失败评论重试同步并完成2011／profile2012限定补验；PR #36按授权整合送合，主线日常包见详情，未发布。 | [任务详情](docs/branches/fix-comment-failure-reconcile.md) |
| `codex/test/feed-supplement-support` | PR #35已合入main，交付可信HTTPS与原评论worker失败重试隔离补验支持；未正式发布。 | [任务详情](docs/branches/test-feed-supplement-support.md) |
| `codex/fix/feed-read-errors` | PR #34已合入main，隔离列表与偏好局部错误并完成D07定点；未正式发布。 | [任务详情](docs/branches/fix-feed-read-errors.md) |
| `feat/feed-interactions-ui` | PR #31已合入main，接通真实互动与评论数、修复竞态恢复；D07已由#34修复，后续补验见独立任务；未正式发布。 | [任务详情](docs/branches/feat-feed-interactions-ui.md) |
| `codex/chore/feed-staging` | PR #32已合入main，交付隔离故障入口与0021部署恢复记录；未正式发布。 | [任务详情](docs/branches/chore-feed-staging.md) |
| `feat/feed-interactions` | PR #29已合入main，补齐帖子账号级赞／藏与复用评论数的批量摘要后端；未正式发布。 | [任务详情](docs/branches/feat-feed-interactions.md) |
| `codex/fix/feed-fault-error-contract` | PR #33已合入main，补齐隔离GET错误注入的严格关联ID契约与TLS回归；非正式发布。 | [任务详情](docs/branches/fix-feed-fault-error-contract.md) |
| `codex/fix/feed-interaction-order` | PR #30已合入main，以持久条件写版本阻止赞藏条件请求迟到覆盖；已部署隔离测试环境。 | [任务详情](docs/branches/fix-feed-interaction-order.md) |
| `codex/feat/feed-ui` | PR #28已合入main：新版列表接推荐／通道／屏蔽／浏览与自适应图片；未部署。 | [任务详情](docs/branches/feat-feed-ui.md) |
| `codex/feat/feed-backend` | PR #27已合入main：真实浏览、跨通道时间游标和账号屏蔽后端；未部署。 | [任务详情](docs/branches/feat-feed-backend.md) |
| `codex/fix/gate-cancellation-freeze` | PR #25已合入main，修复C/V Gate取消误冻结，真实SQL/TLS回归与证据已交付；未部署。 | [任务详情](docs/branches/fix-gate-cancellation-freeze.md) |
| `codex/ci/android-integration-candidate` | PR #23已合入main，交付固定Android集成候选及新增恢复/真机治理连接限定证据；未正式发布。 | [任务详情](docs/branches/ci-android-integration-candidate.md) |
| `codex/ci/android-prerelease` | PR #16已合入main，交付测试签名候选、同机恢复/回滚与vivo S18最小文字图片限定实测；未正式发布。 | [任务详情](docs/branches/ci-android-prerelease.md) |
| `codex/chore/feed-staging` | 维护新版列表共享隔离后端、备份迁移与联调记录，提供正式发布及恢复方案；未正式部署。 | [任务详情](docs/branches/chore-feed-staging.md) |

| `codex/feat/comment-report-moderation` | 真实主评论/单图回复举报、网页处置、系统通知和申诉已接通，合并状态见任务PR。 | [任务详情](docs/branches/feat-comment-report-moderation.md) |
| `codex/feat/report-moderation` | PR #18 已合入main：帖子举报、网页审核和最小系统通知阶段1；评论接入留第二阶段。 | [任务详情](docs/branches/feat-report-moderation.md) |
| `codex/community-flutter-pages` | PR #13 已合入 main，含社区无障碍及联合回归；跨设备 Passkey 延期。 | [详情](docs/branches/community-flutter-pages.md) |

### 已合并或退役的历史工作

以下分支已合并、关闭或被后续实现取代；历史详情与 PR 记录保留，后续开发以 `main` 为基线：

- 评论与回复：[#17 核心](https://github.com/zewbby/HnuHole/pull/17)与[#19 完整业务接通](https://github.com/zewbby/HnuHole/pull/19)已合入main，评论开发结束；[任务详情](docs/branches/feat-comments-backend-text.md)及[合并收尾](docs/branches/docs-comments-merge-delivery.md)保留Android限定验收及延期边界。
- 文字帖：[早期实现与退役交接](docs/branches/community-text-posting.md)；维护资料已整理，T1–T3 原始证据与完整提交历史分别归档。
- 工程基线：[工程决策与早期骨架](docs/branches/engineering-baseline.md)，原分支按用户要求退役，完整历史保留于归档标签。
- 认证与 B5：[认证交接](docs/branches/auth-privacy-handoff.md)、[B5 主线接入](docs/branches/fix-b5-main-integration.md)、[B5 合并记录](docs/branches/docs-b5-integration-merge-record.md)；认证导入 PR [#8](https://github.com/zewbby/HnuHole/pull/8) 已由 [#9](https://github.com/zewbby/HnuHole/pull/9) 取代。
- 帖子图片：[图片 Android 交付](docs/branches/feat-post-image-android.md)、[图片业务合并记录](docs/branches/docs-post-image-merge-record.md)、[图片后端](docs/branches/post-image-media.md)、[图片集成](docs/branches/post-image-integration.md)。
- 图片查看器：[组件](docs/branches/image-viewer-component.md)、[业务接入](docs/branches/image-viewer-business-integration.md)。
- 协作与索引：[协作规范](docs/branches/chore-collaboration-rules.md)、[README 分支索引](docs/branches/docs-readme-branch-index.md)。

## 最近变动

- [PR #35](https://github.com/zewbby/HnuHole/pull/35)：支持原评论worker失败重试隔离补验并封存可信入口与单机性能证据。
- 2026-10-20 · [#34](https://github.com/zewbby/HnuHole/pull/34)：隔离列表与偏好局部错误，修复恢复后详情残留提示。
- 2026-10-20 · [#31](https://github.com/zewbby/HnuHole/pull/31)：接通列表详情真实互动与评论数，并修复账号及未知结果恢复。
- 2026-10-20 · [#33](https://github.com/zewbby/HnuHole/pull/33)：修正隔离GET错误注入的正文及响应头关联ID。
- 2026-10-20 · [#32](https://github.com/zewbby/HnuHole/pull/32)：补齐隔离故障测试入口及0021部署恢复证据。
