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
| `codex/auth-privacy-handoff` | 实现认证、匿名隐私边界和相关验收交接。 | [详情](docs/branches/auth-privacy-handoff.md) |
| `codex/fix/b5-main-integration` | 在主线接入 B5 验收增量并修复闭号与图片擦除边界。 | [详情](docs/branches/fix-b5-main-integration.md) |
| `codex/community-text-posting` | 实现文字帖后端、接口及早期客户端闭环。 | [详情](docs/branches/community-text-posting.md) |
| `codex/community-flutter-pages` | 实现社区页面并推进社区与认证的 Android 验收。 | [详情](docs/branches/community-flutter-pages.md) |
| `codex/image-viewer-component` | 实现独立图片查看组件和 Android 原格式保存。 | [详情](docs/branches/image-viewer-component.md) |
| `codex/image-viewer-business-integration` | 为主 App 接入图片查看入口及九图选取上传前端。 | [详情](docs/branches/image-viewer-business-integration.md) |
| `codex/feat/post-image-android` | 将图片业务及其前置实现通过 PR 交付到主线。 | [详情](docs/branches/feat-post-image-android.md) |
| `codex/chore/collaboration-rules` | 建立分支、提交、PR 审查和协作检查规范。 | [详情](docs/branches/chore-collaboration-rules.md) |
| `codex/docs/post-image-merge-record` | 补记图片业务合入主线的事实与 iOS 剩余事项。 | [详情](docs/branches/docs-post-image-merge-record.md) |
| `feature/engineering-baseline` | 确定 Flutter、Go、通信与持久化的工程基线。 | [详情](docs/branches/engineering-baseline.md) |
| `codex/docs/readme-branch-index` | 将 README 改为分支简表与最近合并摘要。 | [详情](docs/branches/docs-readme-branch-index.md) |


已合并的历史工作：[帖子图片后端](docs/branches/post-image-media.md)、[帖子图片集成](docs/branches/post-image-integration.md)。实现已进入 `main`，详情页保留固定提交与验收证据，不依赖原分支继续存在。

## 最近变动

按合并时间倒序保留最近 5 条，每条一句话说明。

- 2026-10-16 · [#5](https://github.com/zewbby/HnuHole/pull/5)：退役帖子图片后端分支，保留历史交接入口。
- 2026-10-16 · [#4](https://github.com/zewbby/HnuHole/pull/4)：将 README 整理为分支简表与最近合并摘要。
- 2026-10-16 · [#3](https://github.com/zewbby/HnuHole/pull/3)：补齐图片业务交接记录和 iOS 待办。
- 2026-10-16 · [#2](https://github.com/zewbby/HnuHole/pull/2)：接入帖子图片业务，完成 Android S18 约定范围验收。
- 2026-10-15 · [#1](https://github.com/zewbby/HnuHole/pull/1)：统一分支、提交、PR 与协作检查规范。
