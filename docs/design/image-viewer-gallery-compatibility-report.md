# IV01：相册故障定位与原文件兼容回放复验

2026-10-14（Asia/Shanghai）。**用户选择的“保留原文件、使用兼容相册复验”路线通过：vivo S18 上 Fossify Gallery 1.14.0 能自动播放 SLOW WebP，约每 2 秒换色，两轮后停在蓝色；操作者与完整录像均确认。**原短有限 WebP、GIF、无限 WebP 也有本轮限定回放证据，四份文件播放后的 SHA256 均与源文件相同。vivo Gallery 9.4.6.13 的首开、时序和循环失败仍保留，没有把更换相册记成修复了 vivo 系统相册。

[机器证据](image-viewer-gallery-compatibility-verification.json)与台账 `currentImageViewerGalleryCompatibility` 是本轮入口；[上轮身份报告](image-viewer-gallery-identity-report.md)保留原版本及当时结论。本轮没有修改组件、示例、依赖或锁，不重做封装，不接主 App，产品原生保存继续默认关闭。

## 版本、授权与实施范围

- 工作目录 `E:/Hnuhole-image-viewer-component-20261012/repo`；分支 `codex/image-viewer-component`；origin `https://github.com/zewbby/HnuHole.git`。实际起始 HEAD **cdc31289d573a1dfaaa48384773595622cc37e36**，初始工作区干净；推送前重新核对远端。最终提交由本文件所属 Git 提交确定，完整 HEAD、远端及修改文件清单在任务外 `gallery-rootcause-20261014/logs/compatibility-publication-receipt.json`。
- 用户重新授予空闲 vivo S18 窗口，并选择推荐的保留原文件路线。仅安装原先不存在的 `org.fossify.gallery` 作受控对照；没有改默认相册、替换系统 APK、安装服务端或操作认证环境。**13:10 已结束设备操作。**再次设备操作需要新窗口。
- 手机 vivo S18/V2323A、Android 15/API35、ARM64。Hnu 实验包仍为 **20263017 / 0.0.0-webp-identity20261014-nativecheck**，普通包仍为 20263014；没有新建或安装 Hnu APK。实验 APK SHA256 **adbe747b11c3b0d9e0e6c9dd9ebfd1f282451ad3a0f368d9bfcfa5b6cbdab49a**，82,195,691 B，独立任务测试签名。
- 全包被测摘要仍为 **080aa3dcb7c7b96cde5dce05b82aac0b2000fe2b646681128d8000196ffeffa7**，逐文件核对原 manifest；两份锁文件未改。API、稳定 ID、尺寸/来源输入、会话终态、迟到回调及保存/关闭契约继续见[包 README](../../packages/image_viewer/README.md)。组件不接收账号或秘密，不自行建长期私图缓存。
- 日志根 **`E:/Hnuhole-image-viewer-component-20261012/android-20261013/gallery-rootcause-20261014/logs`**，下文文件名均相对于此处。仅使用既有隔离 E 盘工具、合成素材和本任务单设备 ADB；没有升级或写入认证 SDK、启动/重启共用 ADB。

## 原失败原因及证据界限

本轮先**不录屏**打开 Gal 已保存的标记 SLOW：操作者观察约 15 秒后答复“一直是红色 FRAME 1”。随后只在本任务 SLOW/FAST 间切回，答复“很快闪动且不停”。这两个失败不是只在录屏下出现。`slow-no-recorder-direct.log`、`slow-no-recorder-static.png`、`slow-after-manual-no-recorder.png`保留私有证据；播放后读取原 SLOW，10,352 B/SHA 相同，排除保存或回放改写文件。

只读分析已安装的 `com.vivo.gallery` **9.4.6.13 / 9040613** 可执行包。其 APK SHA256 **b7ad604eee8f883b8ce0290bd23a5277cbac19ecfed36a9837e88d33aa87aced**，181,733,744 B；用现有 Android SDK `dexdump` 检查，没有修改、重签或运行补丁。分析定位：

| 位置（该版本 classes.dex） | 静态事实 | 与实测的关系 |
|---|---|---|
| `com.android.gallery3d.app.s0$d0.run()`，代码偏移 `0x40f82c` | WebP 动画 runnable 调用 `FrameSequence.State.getFrame`，偏移 `0x40f92c`，返回的 long 延时被丢弃 | 未使用源文件每帧 2000ms |
| 同方法 `0x40fa1a`、`0x40fa20` | 固定加 100ms 后交给 Handler 调度下一次 | 能解释观察到约 0.1 秒调度的快速换色 |
| 同方法帧索引推进 | 对帧数取模，未读取或按有限 loop count 终止 | 与两轮文件持续播放的失败一致 |

`s0.j2` 的启动路径创建这一个 runnable。相邻 `FrameSequenceDrawable` 有循环处理能力，但该自定义 runner 未使用它。以上是已安装版本代码中的具体时序/循环缺陷；**没有运行时 hook/调用栈证明此次画面逐次经过该函数**。精确限定到 user 0 的 Gallery PID/tag 日志为空，未为取证打开全局日志。**首次外部打开停在首帧的内部触发条件仍未完全定位**，不能把“继承 FAST 状态”或某个缓存键写成已证明原因。

WebP 原文件声明的是毫秒帧时长和有限播放次数，loop=0 才表示无限。[WebP 官方容器规范](https://developers.google.com/speed/webp/docs/riff_container) 保存端改为 loop=0、改帧时长或转 GIF 都会改变用户原文件；组件也不能修复外部系统相册的调度。因此本轮按用户选择，在保持文件不变的前提下验证一个可用相册，不扩大为系统相册 fork、自研解码器或生产原生桥。

## 兼容相册来源与本轮实际回放

安装 [Fossify 官方 1.14.0 发布包](https://github.com/FossifyOrg/Gallery/releases/tag/1.14.0) `gallery-29-foss-release.apk`，38,538,363 B，SHA256 **cfa321d7467b116741689f8f118b46011c882a4c2359b9320111f87c998af373**，与官方资产 digest 一致。现有隔离工具检查包名 `org.fossify.gallery`、code29/name1.14.0、min26/target36，v2 验签 PASS，证书 SHA256 **affdb124d3f4720c2f98dbca9eacba0514fba4306e20a2786c861c3c0d6ff292**。实际 APK 未声明 INTERNET；其最低版本不改变组件 min24。没有将它添加为组件依赖或承诺所有系统默认相册可用。[该版本 PhotoFragment](https://github.com/FossifyOrg/Gallery/blob/1.14.0/app/src/main/kotlin/org/fossify/gallery/fragments/PhotoFragment.kt) 使用现成 WebPDrawable；是否正确以本次实机为准。

所有回放都显式打开 `org.hnuhole.image_viewer_component.nativecheck` 所有的确切合成 MediaStore URI，读取前再核对 owner、文件大小、扩展名和源 SHA；没有打开个人图片原文件。进入后不触屏，不拖动、不切图救活动画。

| 原文件 | 本轮实机结果 | 证据范围 |
|---|---|---|
| 标记 SLOW：`original (3).webp`，192×144，2000/2000/2000ms、rawLoop2 | **PASS**：自动红绿蓝、两轮、约 2 秒换帧、末帧蓝色停止 | 操作者“OK，没问题”＋连续录像；第一次因权限处理错过动画的观察记 INCONCLUSIVE，不算通过 |
| 原短有限：`original.webp`，96×72，80/120/200ms、rawLoop2 | **PASS，限定自动播放和有限停止** | 稳定目标画面有两组 RGB，之后保持蓝；入场过渡有额外颜色，不能据此精算加载期间总启动次数 |
| 原 GIF：`original.gif`，96×72，80/120/200ms、GIF repeat2 | **PASS，限定自动变化和有限停止** | 首轮红帧被入场过渡遮挡，可见后续完整 RGB 和蓝色结束；不登记精确全部 3 轮通过，GIF repeat2 与 WebP rawLoop2 含义不同 |
| 原无限：`original (2).webp`，96×72，80/120/200ms、rawLoop0 | **PASS，限定观察窗内持续自动循环** | 稳定画面约 0.838–11.896 秒持续 RGB，无输入；不是无限时长或资源预算通过 |
| 以上 4 份播放后原文件 | **PASS** | `fossify-*-after-playback.json` 中实际逐字节 SHA 与源文件一致，无转格式、降质或循环改写 |

SLOW 录像 `fossify-slow-retry-20261014-125932.mp4` 可解码时长 **19.1131 秒**。实际 mediaTime：红0.208856→绿1.830444→蓝3.821622→红5.816100→绿7.833822→蓝9.863233，随后至录像结束保持蓝。四个完整相邻间隔约1.991、1.994、2.018、2.029秒；录像在打开后554ms启动，首段不是完整帧时长测量。用户同时现场核对自动开始、速度及有限结束。

短有限、GIF、无限录像实际时长分别17.211111、9.190911、12.026311秒；不把请求的 screenrecord 时长当实际录像长度。复核使用已有 Edge 软件视频解码、连续播放及 `requestVideoFrameCallback.mediaTime`，短片以半速离线观察；未生成替身动画或在手机上切图。入场过渡与稳定目标分别分析，毫秒间隔受录屏采样影响，不作精密定时保证。完整转换序列与录像 SHA 在机器证据中；原录像/截图仅本机保留，不发布图库缩略图或状态栏。

## 检查、权限和清理

本轮新增执行：官方 APK digest、现有隔离 `apksigner verify --verbose --print-certs` 与 `aapt dump badging/permissions`；单台相册回放、四份播放后字节核对、权限恢复；最后文档 JSON、链接、范围、manifest/锁、非 IV01 台账未变及 `git diff --check`。具体命令、退出码及日志见机器证据。APK 工具日志在父级 `android-20261013/logs/gallery-fossify-{signature,badging,permissions}.{log,json}`。

**本轮不重新运行 Flutter analyze/test/bundle/Android build。**包、示例和锁零改动；最后源码版本已有包90＋示例5、两处分析、bundle、两份 ARM64 原生构建/验签的实际 PASS，命令和日志在[身份报告](image-viewer-gallery-identity-report.md#最后修改后的宿主原生构建与版本)及对应 JSON。此处引用该版本证据，不登记新的宿主或构建通过。任何后续源码修改都应重跑受影响检查。

操作者曾授予 Fossify 全部照片权限；第一次收回后又授予，期间只操作确切合成 URI。13:10 收回 user0 的 `READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`、`READ_MEDIA_VISUAL_USER_SELECTED`，三项系统实读均 false，旧 `READ_EXTERNAL_STORAGE` 也为 false。Fossify 保留安装，未设置默认相册；再次使用可能需重新由用户授予所选照片权限。恢复验证脚本第一次误取 dumpsys 末尾重复的 user0 小节而报错，修正读取第一个完整用户权限节后实读通过；并非权限撤销失败。

本轮没有改系统设置：最终字体1.0、自动旋转1、触点0、指针0、无障碍0、辅助服务列表空。已停止本任务 PID20148/5038 服务并删除本轮私钥、公钥；没有启动、停止或重启共用服务。所有自有远端录像已精确删除。第三方 APK/DEX 诊断副本按确切路径清理并留 SHA 清单；小型本地证据保留 Git 外。现成 E 盘隔离工具及 Hnu 测试包保留供剩余平台复验；旧视频 profile/cache 的历史删除 BLOCKED 不重试、不绕过。

## 继续验收的条件与步骤

1. 获取新的单台空闲窗口，社区优先；只读核对设备、相册版本、任务包版本、工具写入隔离及磁盘。不得为复试启动/重启共用 ADB 或使用认证环境。
2. 在实验示例开启限定 nativecheck 保存入口，保存合成原文件，核对实际 URI 的 owner/MIME/大小/SHA。只将这些文件授予相册读取；不要授予全图库或浏览个人图片。
3. 对确切自有 URI 使用显式相册组件 `org.fossify.gallery/.activities.PhotoActivity` 的 ACTION_VIEW，读权限 flag 与新任务入口；先记录再打开短动画，SLOW 从打开起不触屏观察至少15秒，分别登记自动开始、帧号/速度、两轮结束。回读原文件 SHA。Fossify 升级或其他设备必须重验。
4. vivo Gallery 9.4.6.13 仍 FAIL。若厂商修复/用户提供新的受控版本，单独复验外部首开与内部切回的 SLOW/短有限/无限、原时序、有限结束及播放后 SHA。不能用 Fossify PASS 关闭这个失败，也不自动升级手机系统或默认相册。
5. Android API24–28 权限拒绝/撤销、完整格式/放大旋转/后台/读屏矩阵仍 NOT_RUN；沿用[单台清单](image-viewer-android-checklist.md)，历史手势与保存竞争证据保留原 APK 版本。
6. iOS 原生构建/Photos/权限/回放/VoiceOver **NOT_RUN**：需独立 Mac/Xcode、受控保存入口和获准设备后执行 `flutter build ios --debug --no-codesign --no-pub`，再逐项平台验证。MIV13 手机资源预算 **NOT_DEVELOPED_NOT_FIXED**，MIV14 业务接入 **NOT_DEVELOPED_NOT_INTEGRATED**。

选定相册的原文件兼容路线完成本轮有范围验收；IV01 整体仍部分验收，M3/双端与 M4 未完成。原生保存默认关闭，不发布 Release、不部署、不合并 main。
