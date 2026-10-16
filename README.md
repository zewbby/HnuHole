# 海南大学树洞

面向海南大学校内人员的封闭树洞社区，用于吐槽、互助、找搭子、发表想法和分享生活。致力于打造一款匿名程度尽可能高的匿名论坛，保护在校师生的个人信息。

当前已从产品设计阶段进入工程方案阶段，首版面向 iOS 与 Android。工程基线已确定为 Flutter/Dart 移动端、Go 服务端和模块化单体后端；仓库采用 monorepo，Go HTTP、PostgreSQL、REST/OpenAPI、服务端会话、移动端本地存储、CI/测试与部署基线已记录，具体云厂商、推送供应商和发布流程仍在后续决策中。

## 帖子图片业务与查看组件（本分支交付）

工作项：独立图片查看组件 → 真实帖子图片业务接入；交付分支 `codex/post-image-integration`，功能与真机记录固定在 `1c8ad33`（修复实现 `fd2e4c0`）。2026-10-16 按用户要求准备合并 main；合并事实及稳定 PR 入口见 [progress](docs/design/progress.md)，未发布或部署。

本任务除 iOS 外的约定范围已完成：

- 独立 `packages/image_viewer`：缩放、长图适宽顶部进入、阅读位置/旋转锚点、手势退出、加载失败重试、生命周期与迟到回调隔离；同一次回顶手势不能退出，全部松手后新下拉才能关闭。
- 帖子最多九图选取/排序/移除、加密原图草稿与进程恢复、逐项上传/补传/失败编辑重试；真实 Go/C/V/PostgreSQL 联调、完整验证后公开、受保护原图读取及访问失效。
- 主 App 通道/我的 → 帖子详情 → 查看器接入；Android10/API29+ 原格式保存默认开启，GIF/动态 WebP 不转换、不静默降质；组件不接收账号凭据或建立长期私有图片缓存。
- vivo S18、Android15/API35 的本轮约定链路真机验收已完成，最终 Debug 包20263116；修复后分析0、相关69项宿主测试、bundle、Android原生构建与验签通过。真实相册保存的九份原字节校验及 Gallery 动画回放有证据，具体范围见 [S18报告](docs/design/post-image-android-device-report.md)、[机器记录](docs/design/post-image-android-device-verification.json)。上轮完整宿主375和后端244保留各自版本，不混算为本轮测试。

**本任务剩余：iOS。**原始选图适配尚未实现，现有图库路径可能重编码，入口继续关闭；后续需 macOS/Xcode 和 iOS 实机完成原始 JPEG/PNG/GIF/WebP 读取、原生构建、安全存储、权限、保存及相册回放、交互验收。Android通过不代表iOS通过。

另列项目级工作：最大九图资源预算、生产存储/配额/备份与存量升级、评论/私信图片消费者及正式发布，不计作本次帖子图片任务未完成。单台 S18 证据不代表所有机型/相册或完整项目已通过。测试窗口已结束；自己的服务/手机映射已收回，Linux私有库/密钥已清理，Windows专用材料清理被自动审批拦截而保留，详见报告。

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
