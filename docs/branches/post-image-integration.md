# codex/post-image-integration

**状态：2026-10-16 已退役，本地和远端分支均已删除。**删除前最终提交 `f4a556d` 与 main `b933c8a` 的文件内容一致，工作区干净。实现、报告和交接记录均保留；iOS 后续从最新 main 新建分支继续。

## 退役清理

- 已删除82处本任务专用 SDK副本、Pub/Gradle缓存、构建目录、APK、测试签名、合成账号材料及临时日志，共约22.52 GiB逻辑文件；保留源码和版本化交接记录。
- **电脑清理尚未全部完成：**剩余 `E:/Hnuhole-post-media-android-20261015/tools` 等专用工具和小型根清单，以及部分忽略的生成文件；最终工具目录删除、生成文件删除均被自动审批在执行前拒绝，只返回 `blocked by policy`。未换用其他机制绕过，不能记为已删除。
- **手机清理尚未执行：**当前无正在运行的ADB/5037连接，等待用户恢复现有连接；没有启动/重启ADB、卸载包或删除媒体。仅清本任务包及归属/散列匹配的合成图片，个人媒体保留。
- 旧M1缓存被认证环境引用，及另一个后端会话目录均保留；其他会话服务、共享SDK和手机个人内容未动。

完整目标清单、实际结果和剩余项见[退役回执](post-image-integration-retirement-20261016.json)。以下保留退役前交付快照。

完成帖子图片前后端联调和主 App Android S18 验收。

核对日期：2026-10-16。

## 进度

经 PR #2 合入 main，PR #3 补齐记录；原分支 dbab372 已同步，功能设备记录 1c8ad33、修复 fd2e4c0。

## 剩余事项

本任务功能范围剩余 iOS：原始选图开发及原生/设备验收。

核对提交：[`dbab372`](https://github.com/zewbby/HnuHole/commit/dbab372c5de2cb6801403cb07e745836b2dfaa43)。

## 详细记录

- [S18 报告](../design/post-image-android-device-report.md)
- [联合报告](../design/post-image-joint-report.md)
- [合并回执](../design/post-image-main-delivery-20261016.json)

## 已完成的工作和验证

工作项：独立图片查看组件 → 真实帖子图片业务接入；交付分支 `codex/post-image-integration`，功能与真机记录固定在 `1c8ad33`（修复实现 `fd2e4c0`）。2026-10-16 已通过 [PR #2](https://github.com/zewbby/HnuHole/pull/2) 合并 main，合并提交 `4fc19baf8655da4b012a0a6dd2c8c9a7b2bab398`；来源分支保留。详见 [progress](../design/progress.md) 与[合并回执](../design/post-image-main-delivery-20261016.json)，未发布或部署。

本任务除 iOS 外的约定范围已完成：

- 独立 `packages/image_viewer`：缩放、长图适宽顶部进入、阅读位置/旋转锚点、手势退出、加载失败重试、生命周期与迟到回调隔离；同一次回顶手势不能退出，全部松手后新下拉才能关闭。
- 帖子最多九图选取/排序/移除、加密原图草稿与进程恢复、逐项上传/补传/失败编辑重试；真实 Go/C/V/PostgreSQL 联调、完整验证后公开、受保护原图读取及访问失效。
- 主 App 通道/我的 → 帖子详情 → 查看器接入；Android10/API29+ 原格式保存默认开启，GIF/动态 WebP 不转换、不静默降质；组件不接收账号凭据或建立长期私有图片缓存。
- vivo S18、Android15/API35 的本轮约定链路真机验收已完成，最终 Debug 包20263116；修复后分析0、相关69项宿主测试、bundle、Android原生构建与验签通过。真实相册保存的九份原字节校验及 Gallery 动画回放有证据，具体范围见 [S18报告](../design/post-image-android-device-report.md)、[机器记录](../design/post-image-android-device-verification.json)。上轮完整宿主375和后端244保留各自版本，不混算为本轮测试。

合并前 GitHub CI：组件与 mobile 分析均0问题，组件112项、受影响mobile130项、bundle、Go test/build/vet及协作检查通过；锁文件保持原样。CI不代替上述真实设备/SQL证据。

**本任务剩余：iOS。**原始选图适配尚未实现，现有图库路径可能重编码，入口继续关闭；后续需 macOS/Xcode 和 iOS 实机完成原始 JPEG/PNG/GIF/WebP 读取、原生构建、安全存储、权限、保存及相册回放、交互验收。Android通过不代表iOS通过。

另列项目级工作：最大九图资源预算、生产存储/配额/备份与存量升级、评论/私信图片消费者及正式发布，不计作本次帖子图片任务未完成。单台 S18 证据不代表所有机型/相册或完整项目已通过。测试窗口已结束；自己的服务/手机映射已收回，Linux私有库/密钥已清理，Windows专用材料清理被自动审批拦截而保留，详见报告。
