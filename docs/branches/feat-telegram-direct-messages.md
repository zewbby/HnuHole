# 私信 Telegram Android 改造：现状与实施边界

2026-10-22合并回执：展示/四导航已合入8fb28d7，#47随后接通隔离开发环境可靠文字收发。用户已授权合并，独立agent审查无阻断且最终head适用CI成功，非GitHub成员批准。未部署/发布；当前状态见[机器回执](../design/direct-message-p1-main-merge-20261022.json)，下方为历史阶段记录。

工作项 DM-TELEGRAM-01，模块 B08/B09，更新于 2026-10-21（Asia/Shanghai）。

2026-10-22合并准备：用户授权合并#47及其#44依赖；#44整合main `90ba0c4`，仅三份交接文档新增记录冲突，保留双方内容，产品代码自动合并。受影响的登录/根导航整合执行 `flutter test --no-pub test/login_home_navigation_test.dart test/direct_message_navigation_test.dart test/email_login_test.dart test/auth_screen_test.dart --reporter expanded`，50 PASS。未重复已验证的字体、UI/IME真机验收；未修改邮箱认证实现。独立审查及精确整合head CI仍待完成，不提前记录已合并。

分支 `feat/telegram-direct-messages` 从本轮 fetch 后的 `origin/main` 建立，基线 `76af92b25eeba8bd5e93339be737314b3c35ea0b`。用户最新要求分支不含 codex 字样，优先于仓库默认前缀。独立工作区位于 E 盘；C 盘创建因空间不足失败，Git 已回滚工作区注册，没有清理其他任务资源。

当前已完成列表/聊天展示层与四入口导航，已提交 [Draft PR #44](https://github.com/zewbby/HnuHole/pull/44)；未合并/发布。真实私信 API 与本地业务持久化仍缺失。以下“现状/规则/接口缺口”为实施前分析快照。

> **同日交付进度：**按用户最新要求，四入口为首页、消息（铃铛）、私信（单气泡）、我的，沿用发帖页固定底栏，未选中线框/选中蓝色实心。消息保持现有系统通知；正式私信入口仅显示暂未开放，聊天夹具继续独立预览。最终完整 Flutter **702 PASS**、聚焦含渲染 **36 PASS**、分析 0、生产 APK 2155/独立预览 APK 2156 构建 PASS。真我 RMX3366/Android14 已安装 2156 并完成约定 UI/IME 验收，早期锁屏阻塞已解除，原失败保留。后端联调未实现，独立 review 与远端 CI 待完成，保持 Draft。见[实施记录](../design/telegram-direct-messages.md)及[机器记录](../design/telegram-direct-messages-verification-20261021.json)。

## 现状与依据

- 主线 `apps/mobile/lib/main.dart` 的 `_openMessages()` 路由为 `SystemNotificationsScreen`，现有未读来自 governance；不能将系统通知计数用作私信计数。
- 主线没有 `apps/mobile/lib/src/messaging`。`packages/openapi/` 和 `services/api/internal/authprivacyhttp/` 未找到私信会话、收发、结果核对、阅读游标或待投消息确认接口。现有身份、帖子、评论、媒体和系统通知接口不是私信接口。
- 指定参考工作区 `HnuHole-telegram-appearance` 的 `docs/design/telegram-android-appearance.md`、共享 `telegram_theme.dart` 和 `assets/fonts/` 已读。主线已具备同套主题及真实 Roboto/Noto Sans SC 字体和许可，沿用其语义色与字族，不重新打包另一套字体。
- 另在只读参考工作区 `HnuHole-ui-system` 找到旧 Flutter 展示实现：`direct_message_models.dart`、`direct_message_screen.dart`、`direct_message_bubble.dart`、`direct_message_composer.dart`、开发预览及 `direct_message_screen_test.dart`。该实现通过类型化投影与回调接入上层；其文档明确生产适配器、本地消息存储和双用户联调尚未实现，不能把夹具接到生产入口。
- 旧时间线为普通 `ListView.builder`，只有全页 `dayLabel`，没有历史游标、加载状态、分页回调或前插锚点保护；已有 TextField 多行、SafeArea、Scaffold 键盘避让和拖动收键盘，但没有本轮真机证据。旧样板部分确认框硬编码 serif，迁移时应继承主线字体。
- 原始 Telegram Android 会话列表、聊天页、键盘截图尚未取得。本轮用户文字提到附图，但当前消息没有可读取附件。旧 Flutter 渲染和 HnuHole 产品图不能替代 Telegram 原图。

## 消息状态与匿名身份规则

- 旧样板 `DmSendState` 为 `sent / sending / unknown / failed`。`onSend` 返回 true 只表示本地持久队列接受，不表示服务端成功；旧预览只在内存模拟这一承诺。
- 发送中和结果未知都在本人气泡旁转圈，不提供点击重试；只有明确失败才显示红色叹号，经确认重试原消息和原身份对。成功无勾选、无已读。未知请求必须先核对，重启不能盲目重发。
- 同一双方身份对跨帖唯一；另一身份对独立，不揭示账号关联。来源帖已有身份必须沿用；首次选择不自动发送或绑定。保留最初来源帖及私人备注。
- 首次联系仅一条成功文字；对方回复前不能发图片。删除或撤回不重置额度。自己身份删除停止重试并执行既有清理规则；对方身份失效停止发送，输入保留供复制。
- 未读按收件身份隔离，只清除实际查看对象及已查看批次，之后新到消息继续未读；打开消息首页和切身份不清全部。不能对外展示已读、在线、正在输入。
- 旧历史仅在本机；平台保留未确认落地的待投副本，接收方本地持久化后才能 ACK。保存失败不能伪装为发送失败，也不能提前 ACK。新机不下载旧机完整历史、不显示旧历史缺失提示。

规则来源：`docs/design/modules/messaging.md`、`messages.md`、`identity.md`，以及旧样板的 `docs/design/mobile-ui-system/telegram-direct-message.md`。B09 交接台账仍注明未实现。

## 接口缺口与可实施边界

| 重点 | 业务缺口 | 前端方案与限制 |
| --- | --- | --- |
| 会话列表及未读 | 身份对会话目录、排序/置顶/隐藏、按身份未读和阅读边界 | 复用 Telegram 列表密度、头像、摘要、时间、角标；收到权威数据后按实际查看范围提交阅读意图，不能凭点击清全箱 |
| 发送反馈 | 私信持久任务、首发额度权威判定、幂等命令与结果核对 | 保留四态和原任务重试，可靠入队后清输入；迟到回执必须有账号/身份对/页面代次围栏 |
| 接收与恢复 | 待投拉取、消息去重、本地持久化及 ACK、重启恢复 | 不复用公开评论或帖子端点，不用内存夹具冒充业务保存 |
| 历史加载 | 本地聊天仓库、稳定排序/游标和本机草稿 | 历史从本地分页；顶部加载/错误重试保留当前消息和阅读锚点；新消息不能强拉正在看历史的用户到底部 |
| 键盘与外观 | 布局可独立实现，原生 IME/手势仍需设备验证 | 复用主线字体主题，按原图确定顶栏、气泡、图标、输入栏；覆盖中文组合输入、键盘显隐、多行及系统返回 |

## 实施顺序与验收计划

1. 补齐原始 Telegram 列表、聊天与键盘截图，确认是否存在本轮未发现的已实现私信后端/客户端工作区及固定版本。若不存在，须明确是否先交付独立展示层；不能自行把生产功能改造降级为演示验收。
2. 在本独立分支按需迁入旧展示组件，与主线共享主题和字体整合，新增会话列表；迁移只取相关源码/测试，不整分支合并旧设计工作。真实生产入口仅在既有后端能力可承载时接线。
3. 聚焦验证身份隔离、未读批次、四态/确认重试/未知不重发、迟到结果围栏、本地分页锚点、键盘及大字小屏。展示替身检查与真实业务检查分列。
4. 实现后执行 Flutter analyze、受影响测试和必要全量回归、Android 构建，配套产品 CI；使用隔离包进行 Android 真机布局、中文 IME、返回与滚动验收。缺业务端点时不能声称双用户收发/真实未读/重启恢复通过。
5. 差异检查后提交并推送本需求分支、创建 PR、附真实验证及剩余项。用户已授权提交 PR；未授权合并或发布。必要验证缺失时按仓库规范保持 draft。

开始阶段仅执行 fetch main、核对源码/契约/规则和工作区；当时测试/构建/真机未执行。此后实际实施与验收以上方交付进度及机器记录为准；不将旧分支结果计为本轮证据。

同日远端检查：8f8c6cd 的私信专项在 setup-android 安装默认旧 tools 包时失败，尚未进入 Flutter 检查；显式指定 platform-tools 修复，精确 SDK/NDK 安装保持不变。失败回执保留于机器记录，最终远端状态以 PR 当前 head 为准。
