# FEED-UI-01 新版帖子列表接线

- 更新：2026-10-19（Asia/Shanghai）。
- 分支：`codex/feat/feed-ui`，独立 worktree `E:/Hnuhole-env/source/HnuHole-feed-ui`。
- 基线：已确认 [后端 PR #27](https://github.com/zewbby/HnuHole/pull/27) 于 2026-10-19 16:35:57 合入，最新远端 main `f1752e10867efb894e1b7bb3bd9a208c14fa74a0`。不依赖未合并分支。
- 目标：保留 Flutter、认证、发帖、评论与受保护图片链路，接入已确认的推荐／通道／屏蔽／浏览量设计，并实现比例单图与横向多图；不做私信。
- 状态：本地限定验证 PASS，PR 待创建；未合并、未部署。最终验证与源码指纹见[机器记录](../design/feed-ui-verification-20261019.json)。

## 实现与使用

生产 `HnuholeApp` 的社区入口使用 `FeedScreen`；默认“推荐”是跨通道时间倒序，纯文字通道选择走服务端授权目录 UUID。选中即切换并清旧游标，仍可选择已屏蔽通道并获得空态。首次进入／刷新从服务端同步偏好，筛选开关开启即加入账号屏蔽集合；完整集合串行 PUT，未知先 GET 核对，未核对成功禁止继续切换并可重试。重置真实保存空集合。跨设备偏好改变后刷新会同步；旧游标失效会重新读取偏好并加载首屏。

`FeedApi` 独立 DTO 与新接口复用原固定 C HTTPS 客户端、安全 header 校验和错误分类，响应先持久续期再发布状态。账号／会话代次变化清内存列表、偏好、游标和浏览数字，迟到响应不跨账号发布；503 保留原会话，401 沿原路径处理。

列表显示 FeedPost 正文与真实 viewCount（只读 K/M）；列表曝光、build、图片查看与通道切换均不登记浏览。详情中正文实际完成一帧布局、与视口相交且路由在前台后才登记；成功总量回写列表，不做本地加一，作者排除与每日去重仍由服务端负责。评论入口进入原详情／评论；原服务端未提供帖子点赞／收藏／评论计数，本次不伪造数字或动作，未知数显示“—”，未接动作禁用。消息按钮仍进入既有系统通知，不新增私信。

发帖继续用原 Composer／确认／受理／上传流程。在“推荐”点加号先选七个真实通道之一，再进入原发帖页；返回对应通道，成功提示仅消费原权威发布事件。已在阅读位置时不强拉回顶部。详情、评论布局及三列详情缩略图保留。

列表媒体由原 manifest／受保护字节／60秒授权 lease 驱动。新增尺寸元数据只用于布局：普通单图在正文媒体列内按原比例完整显示，预览比例上限定义为 2:1 至 3:4，极端比例裁切并提示完整查看；多图轨道高为正文宽度的0.8倍、限制160–260dp，卡宽限制为正文宽度的45%–78%，间距5dp、下一卡部分露出，图像 contain 不拉伸。点击第 n 张仍使用原 ViewerController 对应索引，授权失效立即关闭。字节加载与失败不会改变已经按 manifest 算出的卡片几何；首次 manifest 未到之前仍是加载态，不冒充已知图片比例。

## 设计来源与迁移边界

只选择性迁入旧工作区的 `x_feed.dart`、`x_feed_controls.dart` 和 Telegram theme，并逐项适配真实状态；没有整包覆盖旧分支，没有迁入 messaging、预览路由、来源头像或参考截图。

用户确认来源为旧工作区 `docs/design/ui-reviews/x-feed-recommend-controls.md` 和 `docs/design/mobile-ui-system/x-media-analysis.md`；输入摘要见机器记录。新规则仅覆盖本列表，原全站搜索、热度算法、自定义标签筛选与私信不在范围。实际宿主渲染见[列表](../design/feed-ui/assets/feed-light.png)、[通道](../design/feed-ui/assets/channels.png)、[屏蔽](../design/feed-ui/assets/blocked.png)、[竖图](../design/feed-ui/assets/portrait.png)、[多图](../design/feed-ui/assets/carousel.png)、[深色](../design/feed-ui/assets/feed-dark.png)。图片均为合成夹具，不含真实用户内容。

## 验证、审查与下一入口

本地分析0问题、Flutter全量530项零失败、18项新增UI/媒体及4项新增HTTP检查、六张实际宿主渲染、生产bundle、全插件三ABI Android debug构建通过；真实C HTTPS/一次性PG/race全回归与最终两通道Dart探针、Go host/build/vet、11份OpenAPI及14操作旧契约、19项协作回归也通过。最终命令和源码指纹见机器记录。Android构建只调整本机忽略配置的HTTPS镜像顺序、补用已有API35组件，并校验安装单个16MB官方CMake组件；未改Android源码或依赖版本。专属 `.github/workflows/feed-ui.yml` 覆盖产品分析、测试、bundle、编译探针及实际 Dart→C HTTPS→PG，不以协作 CI 代替产品验证；原 Post images CI 继续全量测试。

宿主渲染／合成资源不代表实体 Android 触控、TalkBack、多机型性能或 iOS 验收。未操作手机、未连接生产、未部署、未更改迁移与服务端生产逻辑。B03/B04/B06/B12仅增加本范围证据，不升级完整模块结果。独立同事／GitHub 成员审查仍需维护者安排，未伪造批准；最终 CI 随 PR 核对。

最终 APK 为 `apps/mobile/build/app/outputs/apk/debug/app-debug.apk`，SHA-256 `6366ed1efd269fa34baa263db6f546e3b6a5b7031f429872dbad60516e4aee21`；早期 `flutter-apk/app-debug.apk` 不作为最终交付证据。未安装或发布。
