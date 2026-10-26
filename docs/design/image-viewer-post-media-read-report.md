# 真实帖子图片读取接线

> **2026-10-26 MEDIA-SEAMLESS-RENEWAL-01（本地分支／未合并／未部署）：** `codex/fix/media-seamless-renewal` 基于 `origin/main@856313c`，帖子图片前台可见时提前约10秒重新验证清单；元数据相同时保留当前图片、解码缓存和查看器，只更新已验证截止时间。共享请求、后台／不可见不续验，原到期计时与撤权／账号代次围栏保留。最终相关回归228项PASS、分析0问题、Android ARM64 debug构建PASS；命令与源码摘要见[任务与验证](../branches/fix-media-seamless-renewal.md)。B03／B06媒体授权回归重开，设备／iOS／远端CI及完整模块结论不提升。

2026-10-15。前端读取接线已实现；本报告不表示发帖图片上传、完整前后端联调或平台验收完成。原钩子阶段保留在[阶段1报告](image-viewer-business-stage1-report.md)。

## 固定版本与范围

- 本轮起点 `a696742f943c1cfe6a5005024dccaf40be752d8f`，独立分支 `codex/image-viewer-business-integration`，目录 `E:/Hnuhole-image-viewer-component-20261012/business-20261015/repo`；源码提交见机器记录。
- 后端固定交接 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587`，实现 `efccade441bfc5d453751a3fac74211b090e8129`，来自 `codex/post-image-media`。已 fetch 并核对，实际读取[该提交契约](https://github.com/zewbby/HnuHole/blob/d893378a8224b9c7a3b9d2bc9681a6ea508d5587/docs/design/post-image-media-contract.md)与 HTTP/DTO 源码；未合并这个分支，也未追入并行社区分支的新提交。
- 查看组件仍原样来自 `bd7458ad94b7f9aea377ef060acf1316a6cfc6de`。本轮只修改 mobile 的帖子调用层、启动装配、相应测试及交接。认证实现、Go、SQL、上传、组件引擎、三份锁文件均未改。
- SDK 为本任务 E 盘独立 Flutter3.47.5/Dart3.13.4 实体目录，Pub/profile/temp/logs 独立于认证/社区任务。未启动/停止其服务，未使用 ADB、手机、模拟器、真实账号或认证材料，未下载工具链或升级依赖。

## 实现和契约

`main()` 现已装配 `PostController(mediaApi:postApi)`、`PostMediaRepository`，并传入原 `loadPostImages`。通道帖子和“我的”详情复用原页面/路由，只在服务端详情声明正数 `imageCount` 时加载媒体。`PostDetail` 与 `PostContent` 严格接纳可选的1–9图片数，只有含图时可空正文；未知字段、0/10/浮点/字符串计数与非法正文仍拒绝。文字命令摘要和发帖验证未放宽。

`PostMediaApi` 是宿主 HTTP 接口，`imageManifest`/`imageBytes` 只由 `PostController` 使用。每次捕获现有会话/授权代次，响应先走原持久续期，再核对当前授权和帖子删除事实。凭据只留在该 HTTP 调用层，不放入 `PostImages`、`ViewerItem`、provider header、路径或错误说明。401/503接现有会话拒绝/不可用处理，访问拒绝终止媒体组；持久续期失败不能交出字节。

清单严格验证帖子、唯一 `mediaId/contentVersionId`、0起连续顺序、真实显示尺寸/EXIF交换关系、帧数/像素/编码预算、保存许可和三份来源。v1 三份来源必须精确等于当前帖/内容ID的 `/api/v1/posts/{postId}/images/{contentVersionId}/original`；不接受绝对URL、其他origin、跨帖路径、查询、转义替代或跳转。HTTP不跟随重定向；校验 `no-store`、无cookie、严格JSON/元数据，字节还须精确长度/MIME、`nosniff` 和 attachment。单张上限10MiB。

`PostMediaRepository.load(postId)` 返回旧 `PostImages` 契约。清单租约最多60秒且不超过响应会话截止，从请求开始用单调计时扣除网络和续期耗时；它是最长离线持有窗口，不能承诺实时收到远端撤销。退出/切账号/冻结/本机删帖、字节401/403/404/503或租约到期终止旧组；到期只允许主动重新读取新组。旧异步结果不能恢复组。所有媒体/保存字节读取共用最多2个并发槽，撤销后排队项不再发请求。

`PostImage.deferred` 延迟预览读取，返回授权的 `MemoryImage`；同一租约的预览/完整查看合并读取，失败后可从查看页重试。`loadSource` 提供原比例显示尺寸。`resolveOriginal` 每次重新走受保护读取，按 JPEG/PNG/GIF/WebP 原格式提供完整字节，无转换/降质。Android API29+保留原文件保存默认开启；iOS默认关闭。这不增加本轮真实相册或动画回放证据。

`PostImages.onRelease` 由宿主提供，详情换组/卸载、拒收跨帖/数量错误或丢弃迟到组时释放租约。撤销清空本层 provider/Future 引用，逐个 evict 自有 MemoryImage（包括预览），不全局清图片缓存。查看器由原路由终止逻辑关闭。已交给系统的保存仍按原组件竞争契约结算，不承诺回收用户已保存副本。九张原图预览的总内存/流量与跨页压力仍需专门验收，双并发不等于总内存预算通过。

含图失败任务明确提示尚不支持编辑；卡片、按钮及控制器均阻止它进入旧“修改文字重试”。没有伪造图片选择、持久原图草稿、媒体命令摘要、上传/补传或恢复功能。

## 本轮实际检查

最终准确命令、计数、源码/锁摘要及日志见[机器记录](image-viewer-post-media-read-verification.json)。日志根 `E:/Hnuhole-image-viewer-component-20261012/business-20261015/logs/`，执行器为同目录 `run-host.ps1`。

| 检查 | 结果 | 范围 |
|---|---|---|
| `flutter analyze --no-pub` | PASS，0问题 | mobile源码/测试 |
| 五个聚焦测试文件，开启实际页面渲染 | PASS，76项 | 严格媒体HTTP、真实控制器续期、内存租约/并发/迟到/撤销、两处实际详情入口与组件路由 |
| 明确列出其余 mobile 测试文件，排除 `post_controller_test.dart` | PASS，315项 | 当前宿主回归；不能称完整测试套件通过 |
| `flutter build bundle --debug --no-pub` | PASS | Dart/kernel/资源打包；不代表原生链接或手机 |
| 三份锁、`packages/image_viewer` 与起点比较 | PASS，未改 | 没有重新封装组件或升级依赖 |
| 页面渲染 | PASS，人工查看实际PNG | `media-delivery-render/post-detail-images.png`，使用合成图，不是线上/真机截图 |

TLS组合测试实际串联 `HttpPostApi → PostController → PostMediaRepository → MemoryImage/原文件resolver`，使用受信 loopback TLS、合成图片及替身会话API/vault；HTTP服务是测试夹具，**不是 C 业务进程或 SQL**。字节缓存测试实际经 Flutter 解码并核对只 evict 自有 provider。GIF/WebP映射测试仅证明格式传递与额外授权请求，不冒称本轮动画/相册通过。

中间分析曾因响应字节变量遮蔽而失败，已修正；新增组合测试第一轮夹具少了旧详情端点的 `post` 外层而失败，修正夹具后通过，未改生产协议。旧日志保留。最终检查均在最后源码修改后执行。此前 `post_controller_test.dart` 的 Windows SQLite临时目录清理 errno32 已在未改动 e0c1280基线复现，本轮没有修它或重复冒称通过；该文件43项未列入315项。新增真实控制器媒体路径和含图任务编辑门槛有独立聚焦测试，仍不替代完整存储回归。

## 剩余工作与复验

1. **完整图片发帖前端未开发**：选图/顺序、持久原图与媒体意图、黄金摘要、逐项上传/补传和跨进程恢复。评论/私信页面及媒体接入继续未开发，不把帖子读取接线当作三类业务完成。
2. **联合链路与 Android业务待验**：在新建的独立装配分支使用前端本轮源码提交和后端d893378，保留双方台账，处理交接冲突；不合并main。按后端契约准备自有迁移0014、受限授权/校验器、C/V Gate及合成帖子数据，运行现有真实客户端联调入口/补媒体夹具，再构建主App原生包。没有正式启用/迁移/联调证据前不称完整链路PASS。手机须新的空闲窗口，重点补九图/动画与EXIF、60秒到期和失效、原字节保存、总内存/流量；已有独立组件TalkBack不重复冒称新业务证据。
3. **iOS/生产分别保留**：Mac/Xcode/iPhone原生构建、Photos/VoiceOver与完整预算仍待验。生产存储、配额、缩略图成本、正式迁移与安全运营证据沿后端待决定项，不因读取可用而关闭。Android最低10/API29，不适配更老系统。

两个源分支正常提交/推送保留；本轮不发布Release、不部署、不合并main、不操作手机或认证/社区环境。
