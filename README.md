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
| `codex/ci/android-prerelease` | 测试签名候选、同机恢复/回滚及vivo S18最小文字图片链路实测通过；未合并/发布。 | [任务详情](docs/branches/ci-android-prerelease.md) |

| `codex/feat/report-moderation` | PR #18 已合入main：帖子举报、网页审核和最小系统通知阶段1；评论接入留第二阶段。 | [任务详情](docs/branches/feat-report-moderation.md) |
| `codex/community-flutter-pages` | PR #13 已合入 main，含社区无障碍及联合回归；跨设备 Passkey 延期。 | [详情](docs/branches/community-flutter-pages.md) |

### 已合并或退役的历史工作

以下分支已合并、关闭或被后续实现取代；历史详情与 PR 记录保留，后续开发以 `main` 为基线：

- 文字帖：[早期实现与退役交接](docs/branches/community-text-posting.md)；维护资料已整理，T1–T3 原始证据与完整提交历史分别归档。
- 工程基线：[工程决策与早期骨架](docs/branches/engineering-baseline.md)，原分支按用户要求退役，完整历史保留于归档标签。
- 认证与 B5：[认证交接](docs/branches/auth-privacy-handoff.md)、[B5 主线接入](docs/branches/fix-b5-main-integration.md)、[B5 合并记录](docs/branches/docs-b5-integration-merge-record.md)；认证导入 PR [#8](https://github.com/zewbby/HnuHole/pull/8) 已由 [#9](https://github.com/zewbby/HnuHole/pull/9) 取代。
- 帖子图片：[图片 Android 交付](docs/branches/feat-post-image-android.md)、[图片业务合并记录](docs/branches/docs-post-image-merge-record.md)、[图片后端](docs/branches/post-image-media.md)、[图片集成](docs/branches/post-image-integration.md)。
- 图片查看器：[组件](docs/branches/image-viewer-component.md)、[业务接入](docs/branches/image-viewer-business-integration.md)。
- 协作与索引：[协作规范](docs/branches/chore-collaboration-rules.md)、[README 分支索引](docs/branches/docs-readme-branch-index.md)。

## 最近变动

按合并时间倒序保留最近 5 条，每条一句话说明。

- 2026-10-18 · [#18](https://github.com/zewbby/HnuHole/pull/18)：合入帖子举报审核与最小系统通知阶段1，评论接入保留第二阶段。
- 2026-10-18 · [#15](https://github.com/zewbby/HnuHole/pull/15)：补记社区PR #13的合并事实和宿主、SQL、设备验收边界。
- 2026-10-18 · [#13](https://github.com/zewbby/HnuHole/pull/13)：合入社区无障碍与主线图片/认证整合成果，跨设备 Passkey 保留待验。
- 2026-10-18 · [#14](https://github.com/zewbby/HnuHole/pull/14)：归档文字帖原始证据并退役历史分支。
- 2026-10-17 · [#12](https://github.com/zewbby/HnuHole/pull/12)：退役工程基线分支并保留完整历史归档。
