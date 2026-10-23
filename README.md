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

`main` 是项目基线。当前工作分支如下；历史实现、验收文档和 PR 记录继续保留。

| 分支 | 状态 | 进度详情 |
| --- | --- | --- |
| `main` | 项目基线 | [详情](docs/branches/main.md) |
| `test/direct-message-device-recovery` | 私信真实双设备接替、强杀及整机重启增量补验通过；真实掉电按用户要求暂列未验。 | [任务详情](docs/branches/test-direct-message-device-recovery.md) |
| `feat/direct-message-governance` | 已合并 main [PR #52](https://github.com/zewbby/HnuHole/pull/52)；限定验收、SKIP／NOT_RUN 保留，未发布。 | [任务详情](docs/branches/feat-direct-message-governance.md) |
| `feat/direct-message-chat-completion` | 已合并 main [PR #51](https://github.com/zewbby/HnuHole/pull/51)；第二阶段限定原生验收通过，未发布。 | [任务详情](docs/branches/feat-direct-message-chat-completion.md) |
| `feat/email-auth-flow` | 邮箱接入交付分支；长时间关机后重启仍未验证，保留待继续核验。 | [交接](docs/branches/feat-email-auth-flow.md) |

### 本轮退役（2026-10-23）

| 已合并分支 | 合并 PR |
| --- | --- |
| `codex/fix/auth-feedback` | [PR #53](https://github.com/zewbby/HnuHole/pull/53) |

### 本轮退役（2026-10-22）

以下 18 个已合并分支已从远端退役；对应 PR 和历史详情仍可查阅。

| 已退役分支 | 合并 PR |
| --- | --- |
| `codex/community-flutter-pages` | [PR #13](https://github.com/zewbby/HnuHole/pull/13) |
| `codex/docs/community-pr13-merge-record` | [PR #15](https://github.com/zewbby/HnuHole/pull/15) |
| `codex/feat/feed-backend` | [PR #27](https://github.com/zewbby/HnuHole/pull/27) |
| `codex/feat/feed-ui` | [PR #28](https://github.com/zewbby/HnuHole/pull/28) |
| `codex/feat/telegram-android-appearance` | [PR #37](https://github.com/zewbby/HnuHole/pull/37) |
| `docs/auth-entry-delivery` | [PR #41](https://github.com/zewbby/HnuHole/pull/41) |
| `docs/auth-flow-final` | [PR #38](https://github.com/zewbby/HnuHole/pull/38) |
| `docs/direct-message-p1-delivery` | [PR #49](https://github.com/zewbby/HnuHole/pull/49) |
| `docs/email-auth-delivery` | [PR #46](https://github.com/zewbby/HnuHole/pull/46) |
| `docs/registration-delivery` | [PR #43](https://github.com/zewbby/HnuHole/pull/43) |
| `docs/session-resume-delivery` | [PR #50](https://github.com/zewbby/HnuHole/pull/50) |
| `feat/auth-entry-flow` | [PR #39](https://github.com/zewbby/HnuHole/pull/39) |
| `feat/direct-message-text-reliability` | [PR #47](https://github.com/zewbby/HnuHole/pull/47) |
| `feat/feed-interactions` | [PR #29](https://github.com/zewbby/HnuHole/pull/29) |
| `feat/login-home-recommended` | [PR #40](https://github.com/zewbby/HnuHole/pull/40) |
| `feat/registration-wizard-ui` | [PR #42](https://github.com/zewbby/HnuHole/pull/42) |
| `feat/telegram-direct-messages` | [PR #44](https://github.com/zewbby/HnuHole/pull/44) |
| `fix/session-restore` | [PR #48](https://github.com/zewbby/HnuHole/pull/48) |

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

- [PR #52](https://github.com/zewbby/HnuHole/pull/52)：接通私信治理、生命周期清理和隐私本地通知；保留原生与生产未验项。
- [PR #51](https://github.com/zewbby/HnuHole/pull/51)：接通九图私有收发、会话管理和两分钟撤回。
- [PR #53](https://github.com/zewbby/HnuHole/pull/53)：优化登录注册错误反馈、邮箱验证码说明和认证弹窗交互。
- [PR #48](https://github.com/zewbby/HnuHole/pull/48)：普通开发重启保留原会话，安全冻结仍要求明确恢复。
- [PR #47](https://github.com/zewbby/HnuHole/pull/47)：接通隔离环境可靠文字收发、持久队列、ACK与阅读分离及基础未读草稿。
