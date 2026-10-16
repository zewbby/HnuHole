# 图片查看器前端接入：阶段 1

> **2026-10-15 真实帖子图片读取已接线：**前端固定源码 `b5ab3969870daa43b9d40919311d68f1d4cdca61` 对接后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587` 契约；main/通道/我的→详情已装配受保护读取、最长60秒租约、逐个内存缓存释放与原格式保存resolver。分析0、聚焦76项、其余315项及bundle PASS；完整Windows控制器文件43项保留已复现SQLite清理故障，未计PASS。两个源分支未合并/部署，本轮没有手机或服务操作；完整C进程/SQL联调、业务原生构建/真机未验，上传UI/原图草稿/补传恢复与评论私信未开发，iOS独立。见[读取接线报告](image-viewer-post-media-read-report.md)和[机器记录](image-viewer-post-media-read-verification.json)。下方旧钩子/组件记录按原版本与范围保留。

2026-10-15。本轮只实现已有帖子页面的图片接入钩子，不实现图片上传、存储、受保护 HTTP 接口、评论或私信业务。**前端钩子已实现，真实图片业务尚未接通，MIV14 只能记部分实现。**生产 `main()` 没有提供图片加载器，纯文字页面不展示虚构的图片或上传入口。

前端源码已保存为 `433145702406dc25a90eed1ccf7b3abf59e54834`；最终分支 HEAD 为后续交接提交，交付后由 Git 核对远端一致，工作区应干净。

## 基线和隔离

- 独立分支 `codex/image-viewer-business-integration`，工作区 `E:/Hnuhole-image-viewer-component-20261012/business-20261015/repo`。
- 社区实际起始提交 `e0c128033682923d519ea99546d72503b085a99e`，来自 `origin/codex/community-flutter-pages` 已提交版本；该分支尚无图片字段/读取接口、评论/私信页面。
- 从图片分支 `bd7458ad94b7f9aea377ef060acf1316a6cfc6de` 原样引入 `packages/image_viewer`、对应组件历史报告与 Android 基线 ADR；不是重新封装组件。原 Android 112＋7、S18 Release20263021/47项与 TalkBack 等证据仅保留原版本，不冒称本轮手机通过。
- 社区会话正在使用的 `E:/HnuHole-community-f4-20261012/repo` 有并行修改，本轮只读核对、不切分支、不编辑、不提交其文件。认证目录、SDK、服务、数据库和手机均未操作；无 ADB 或设备命令。
- 执行使用本会话独有 E 盘 Flutter3.47.5/Dart3.13.4 SDK，已核对为实际目录而非链接；SDK/bin/cache 不与认证/社区 SDK 共用。Pub/profile/temp/logs 在本接入任务目录。缺少的 drift/sqlite3/glob/native_toolchain_c 只从现成缓存只读复制公开包到独立缓存，未使用秘密、未启动服务、未安装工具链。

## 实现与接线

`apps/mobile/lib/src/posts/post_images.dart` 提供：

- `PostImagesLoader(String postId) -> Future<PostImages>`：调用方先完成授权，再提供对应帖子的图片组。不得返回其他帖子的图片；异常统一脱敏为“图片暂时无法读取”，可主动重试，旧 Future 不能覆盖新帖子或失效会话。
- `PostImages`：固定 `postId`、不可变有序 `images`（0–9张、唯一稳定媒体内容 ID）、调用方拥有的 `ValueListenable<bool> accessGranted`。媒体变化必须用新内容 ID/新组；撤销后当前查看会话终止，不因同一 notifier 改回 true 复活。调用方维持 notifier 生命周期，组件不 dispose 它。
- `PostImage`：独立缩略图 `ImageProvider thumbnail` 和完整查看的 `ViewerItem item`。后者包含完整查看 provider/真实解码尺寸、可选完整原格式 resolver、保存许可和语义说明。缩略图不能代替完整查看来源或原文件；无账号、Bearer、密码、恢复材料参数。provider 的授权与缓存隔离仍由调用方负责。
- `PostImagesSection`：在既有正文后显示三列方形缩略图，等比 cover、不拉伸；加载/失败占位保持格子尺寸，点击从当前索引打开整个帖子图片组。缩略图失败仍可点击查看完整资源。正文保留原 ScrollView/位置，不另造父页面或自动重置列表。

现有接线为 `HnuholeApp.loadPostImages` → `ChannelPostsScreen` / `PersonalPostsScreen.loadImages` → `PostDetailScreen.loadImages` → `PostImagesSection` → `HnuImageViewer`。所有参数可选，旧文字路径保持无媒体加载。宿主业务实现完成后只需提供 `PostImagesLoader`，不需要再次改图片引擎/手势。

查看路由和 `ViewerController` 由前端接入层创建/释放。监听现有 `PostController` 的授权代次/可用状态和帖子删除事实，通过布尔租约约束媒体；这些业务身份值不传入查看组件。换帖子、访问撤销、父页撤下会终结旧查看会话。关闭只移除所拥有的查看路由，不误弹上面的其他对话框。帖子被删除时即使详情被查看器覆盖，也移除对应详情路由，避免返回空白已删除页面；查看器分别结算退出。已进入系统的保存仍遵循组件原契约，不承诺撤销相册副本。

Android 默认原文件保存继续开启，单图业务许可/完整 resolver/成功加载/前台有效会话仍必需；只查看不取原文件。iOS 默认不自动启用。主 App 的 `minSdk` 按用户既定统一要求提高至29；不新增旧 Android 适配或存储权限。本轮未改认证、Go、SQL、上传接口或存储实现。

## 必要验证与边界

日志根 `E:/Hnuhole-image-viewer-component-20261012/business-20261015/logs/`，`run-host.ps1` 记录具体命令、工作目录、源码前后摘要与锁摘要。

| 检查 | 实际结果 | 证明范围 |
|---|---|---|
| `flutter pub get --offline --enforce-lockfile` | PASS | 主 App 增加21个组件所需直接/间接依赖，既有锁条目的版本、来源、摘要均未改；两份组件锁原样保留 |
| `flutter analyze --no-pub` | PASS | mobile当前源码/测试，最初两条括号风格提示已修复 |
| `flutter test --no-pub --reporter=expanded test/post_images_test.dart test/post_screens_test.dart`（本轮渲染环境） | PASS | 新接入契约、已有帖子页及新增路由/滚动/删除组合；精确计数/命令见机器记录 |
| 明确列出全部 `test/*_test.dart`，排除 `post_controller_test.dart` | 290 PASS | 除已复现 Windows 基线清理故障文件外的宿主回归；不是全套测试通过 |
| `flutter build bundle --debug --no-pub` | PASS | Dart/kernel/资源打包，不代证新主App原生构建或设备 |
| 完整 mobile 测试首轮 | FAIL：300 PASS/31 FAIL | 31项均在既有 SQLite 控制器 fixture 清理目录报 Windows errno32；原始日志保留 |
| 未改动 e0c1280 基线单项复现 | FAIL，相同 errno32/同清理位置 | 独立 baseline worktree、锁定原依赖；确认该故障存在于本次接入之前，不改当前社区存储/测试来消除范围外失败 |
| 原生 Android/iOS、真实业务 HTTP/SQL、手机交互 | NOT_RUN | 本阶段未运行，真实媒体接口尚无，不占用社区手机，不重复 TalkBack |

前端聚焦测试包含：统一格子尺寸、点击第二张完整长图、无原文件读取的查看与保存禁止、媒体/授权撤销、覆盖对话框时只移除自有路由、旧加载器迟到、跨帖错误脱敏与主动重试、空组/重复ID/上限、两个真实详情入口传参、关闭后原滚动位置、查看器覆盖时帖子删除返回。页面渲染使用仓库正式 F1-19 作为结构参考，查看真实 Flutter `actual-page-render/post-detail-images.png` 后登记；合成素材只属于测试，不能代证线上图片链路。

完整测试首轮和基线错误分别在 `integration-mobile-all-tests.log`、`baseline-controller-repro.log`：`post_controller_test.dart` fixture 的 `_Fixture.close` 先关闭库/控制器再删除本任务临时目录，Windows仍报文件占用；未确认具体未释放句柄或跨平台修复，不能归因为认证失败或声称已修复。该文件43项未重新记作全通过；后续在社区存储任务修复/隔离Linux运行。本轮不为排除它编造测试筛选参数，使用实际文件列表记录。

## 两个会话的交接

本会话只维护前端钩子。新会话建议分支 `codex/post-image-media`、独立目录 `E:/Hnuhole-post-image-media-20261015/repo`，从社区已提交基线建立；负责真实帖子图片清单/上传/存储/受保护读取和前端 loader 适配。不要修改本会话目录或社区验收目录；不要自动合并其他分支。先核对最新版 `post_images.dart`，明确内容ID、post归属、顺序、真实尺寸/格式、缩略/完整来源、保存许可及撤销事件；后端绝不能要求查看器自行保存账号/Bearer或建立长期公开私有缓存。

可直接复制的 prompt 在本任务外部 `image-business-new-session-prompt.txt`，其全文同时保存在[接力任务](image-viewer-media-next-session.md)。不是已经创建/消息发送给另一个会话；由用户自行交给新会话。

后续真实业务接线需要：媒体层返回真实 `PostImages`、启动时注入 `loadPostImages`，补真实上传/读取授权与失效、保存原字节/动画和阶段2集成回归。评论/回复和私信缺少真实页面/协议，继续 NOT_DEVELOPED，不在这轮虚构入口。iOS与其他硬件平台验收继续单列；不把阶段1前端准备写成完整 MIV14 或正式双端交付。提交/推送只针对本接入分支，不合并main、不发布、不部署。
