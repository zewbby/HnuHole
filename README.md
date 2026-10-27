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

- [通知与互动收件箱](docs/branches/feat-notification-inbox.md)：[PR #81](https://github.com/zewbby/HnuHole/pull/81) 已合并四分类通知、全App身份同步和统一五项发帖导航，主线包已构建、同机开发服务已更新，待用户试用。

- [帖子图片平滑续验](docs/branches/fix-media-seamless-renewal.md)：`codex/fix/media-seamless-renewal` 在权限续验成功且图片未变时保留画面与缓存，避免周期性重载；已由[PR #76](https://github.com/zewbby/HnuHole/pull/76)合入main，17项CI通过，未安装／部署。

- [身份转帖](docs/branches/feat-post-reposts.md)：`feat/post-reposts` 提供持久化私人归档、条件写入与接线契约，已整合到个人页分支；未合并。
- [个人页与私人转帖](docs/branches/feat-personal-profile-mood.md)：`feat/personal-profile-mood` 实现五栏缩放、身份切换和共享喜欢／收藏，已接入私人转帖归档；未合并。

`main` 是项目基线。当前工作分支如下；历史实现、验收文档和 PR 记录继续保留。

| 分支 | 状态 | 进度详情 |
| --- | --- | --- |
| `fix/image-viewer-gestures` | 已合并 main [PR #77](https://github.com/zewbby/HnuHole/pull/77)：图片上下拖动平滑退出、背景透出及切图缓存修复，未装机/部署。 | [任务详情](docs/branches/fix-image-viewer-gestures.md) |
| `main` | 项目基线 | [详情](docs/branches/main.md) |
| `feat/shared-rate-limit-abuse-control` | [PR #73](https://github.com/zewbby/HnuHole/pull/73) 已合入main：共享准入、上传字节与草稿/队列完成，指定Android及最终CI限定通过，未生产发布。 | [任务详情](docs/branches/feat-shared-rate-limit-abuse-control.md) |
| `codex/feat/post-detail-comments` | 已合并 #71：连续评论与排序、页内回复和首条即时展示；真我2427弱网及20分钟操作限定通过，图片入口支持GIF。 | [任务详情](docs/branches/feat-post-detail-comments.md) |
| `codex/fix/feed-refresh-cancel` | 已合并 main [PR #69](https://github.com/zewbby/HnuHole/pull/69)：刷新回滑可取消，纯享手势隔离，加载高亮留在颜文字内。 | [任务详情](docs/branches/fix-feed-refresh-cancel.md) |
| `codex/feat/feed-scroll-smile-refresh` | 已合并 main [PR #65](https://github.com/zewbby/HnuHole/pull/65)：沉浸阅读、发帖入口交接与 `:)` 刷新；未安装／发布。 | [任务详情](docs/branches/feat-feed-scroll-smile-refresh.md) |
| `feat/identity-avatar-onboarding` | 头像上传与首次身份设置已合入 main [PR #63](https://github.com/zewbby/HnuHole/pull/63)，开发后端与真我日常2315已配套更新，未生产发布。 | [任务详情](docs/branches/identity-avatar-onboarding.md) |
| `fix/direct-message-header-density` | 送审快照：私信顶部布局与语义点击已交付[PR #62](https://github.com/zewbby/HnuHole/pull/62)，2315已覆盖安装；最终CI／合并状态以PR回执为准，未发布。 | [任务详情](docs/branches/fix-direct-message-header-density.md) |
| `fix/direct-message-identity-loading` | 空身份修复、右上快捷切换与身份管理往返保持绑定已送审[PR #60](https://github.com/zewbby/HnuHole/pull/60)，2313限定通过；合并与CI回执见PR，未发布。 | [任务详情](docs/branches/fix-direct-message-identity-loading.md) |
| `fix/mobile-navigation-refresh` | 已合并 main [PR #57](https://github.com/zewbby/HnuHole/pull/57)；五项限定验收、动图原生保存与短时帧性能已测，未发布。 | [交接](docs/branches/fix-mobile-navigation-refresh.md) |
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

- [PR #81](https://github.com/zewbby/HnuHole/pull/81)：四分类通知、跨模块身份同步与统一发帖导航已合入主线，检查通过，主线包已构建、同机开发服务已更新，待用户试用。
- [PR #77](https://github.com/zewbby/HnuHole/pull/77)：图片上下拖动跟手缩小并渐隐露出原页面，修复切图空白及退出闪字，最终CI通过，未装机/部署。
- [PR #78](https://github.com/zewbby/HnuHole/pull/78)：同步图片权限提前续验PR76的真实合并及检查回执。
- [PR #76](https://github.com/zewbby/HnuHole/pull/76)：图片提前续验并复用缓存，避免正常浏览周期性闪烁，17项CI通过，未装机／部署。
- [PR #74](https://github.com/zewbby/HnuHole/pull/74)：同步共享动作限流PR73的主线合并与交接回执。
