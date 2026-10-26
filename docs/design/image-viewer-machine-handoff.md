# 图片查看组件换机交接

> **2026-10-26 IMAGE-VIEWER-GESTURES-01（PR77待合并）：** `fix/image-viewer-gestures` 从 `origin/main@856313c` 建立，按用户要求不带 codex 前缀。图片上下拖动跟手缩小、背景渐隐露出原页面，短拖回弹、完成动画后退出；取消结束提示闪屏，加入有界会话缓存与横滑目标页准备，修正状态栏。帖子、编辑器、私信共用透明路由；长图、双指、缩放、撤销及原文件保存护栏保留。实现与最终验证见[任务记录](../branches/fix-image-viewer-gestures.md)和[机器证据](image-viewer-gestures-verification.json)。已提交推送[PR77](https://github.com/zewbby/HnuHole/pull/77)，整合主线PR76后相关118项回归、分析及Android构建PASS；等待最终提交远端CI，未合并/部署，真机手感及 iOS 本轮 NOT_RUN；旧模块总裁决不提升。

> **2026-10-15 主App帖子图片S18真机联调已完成约定范围：**修复实现 `fd2e4c04f48b29ddda0142660188988c4a655f5f`，分支 `codex/post-image-integration`。实际原生Picker/原图跨进程恢复、九图C/V/SQL上传及缺项补传、失败编辑同任务RETRY、受保护查看、Gal原格式保存与Gallery动画回放、删帖/退出/切账号/迟到隔离取得本轮证据；修复成功核对后残留旧错误提示。最后修改后分析0、相关宿主69、Python守卫15、bundle、Android Debug20263116构建/验签及上机复验PASS。手机窗口结束，系统设置已恢复、自己的App/后端已停、映射已撤；Linux专用私钥/库已清理。Windows清理被自动审批拦截，材料仍保留且私有目录ACL受限，不能写成已清理。iOS原始选图仍未实现，最大资源预算/库存升级/生产与评论私信另列；不重测旧TalkBack、不宣称全模块/双端通过。见[本轮报告](post-image-android-device-report.md)与[机器记录](post-image-android-device-verification.json)。下方旧记录保留各自版本与范围。

> **2026-10-15 主App帖子图片真机验收的非手机准备已完成：**实现 `2eeb19ce87542aed9e0c57874e8d6b3478df946d`，本任务独立kit `E:/Hnuhole-post-media-android-20261015`。新主App/probe两个API29+包构建与验签、分析0、原图宿主10项、离线守卫15项/设备命令守卫4项、专用真实C/V/Goose/受限空PG重启及Windows HTTPS均PASS；自己的后端已停。没有调用ADB或操作手机，PMA01–14全部NOT_RUN，等待另一会话释放；旧组件TalkBack不重测。按用户要求暂留独立APK/签名/空库/工具供直接配合，过期先核就绪清单。见[准备报告](post-image-android-preparation-report.md)、[机器记录](post-image-android-preparation-verification.json)、[集中SOP](../../tools/post-media-android/README.md)。下方旧结果保留原源码和范围。

> **2026-10-15 帖子图片真实前后端联调完成：**联合分支 `codex/post-image-integration`，源码 `31e82df6ad0f8345471705cf78e6e0f463beecfb`（前端075b567＋后端d893378）。真实C/V进程、Goose/受限PG、Flutter生产页面/API/原图草稿/补传/读取/保存resolver，19检查点全部PASS；修复旧上传暂停状态污染新RETRY。当前分析0、完整宿主375（零排除）、后端SQL/race244、Python4/OpenAPI6、编译/vet、Windows bundle与Android原生构建/验签PASS。没有手机或其他会话服务操作；原生业务真机、iOS原始选图、总预算/生产与评论私信另列。见[联合报告](post-image-joint-report.md)和[机器记录](post-image-joint-verification.json)。下方各分支旧记录保留原版本与范围。

> **2026-10-15 帖子选图上传前端已补齐：**实现 `5cd5fdb8f3766bb5ae5840fa7546eda6739fd98c`，最多9图/排序/移除、加密原图草稿、媒体摘要、逐项补传和重启核对已接现有写帖页。最终分析0、完整mobile374项（零排除，含修复后的控制器43项）、bundle及Android API29+原生构建/验签PASS。后端仍固定d893378独立分支，真实C/V/SQL联调和业务手机未验；本轮未操作手机/服务。iOS选图库会重编码原图，原格式选图尚未实现、入口保持关闭，不能只写待验；评论私信/总资源预算另列。见[本轮报告](post-image-composer-report.md)和[机器记录](post-image-composer-verification.json)。下方旧结果保留原版本，不代证当前。

> **2026-10-15 真实帖子图片读取已接线：**前端固定源码 `b5ab3969870daa43b9d40919311d68f1d4cdca61` 对接后端 `d893378a8224b9c7a3b9d2bc9681a6ea508d5587` 契约；main/通道/我的→详情已装配受保护读取、最长60秒租约、逐个内存缓存释放与原格式保存resolver。分析0、聚焦76项、其余315项及bundle PASS；完整Windows控制器文件43项保留已复现SQLite清理故障，未计PASS。两个源分支未合并/部署，本轮没有手机或服务操作；完整C进程/SQL联调、业务原生构建/真机未验，上传UI/原图草稿/补传恢复与评论私信未开发，iOS独立。见[读取接线报告](image-viewer-post-media-read-report.md)和[机器记录](image-viewer-post-media-read-verification.json)。下方旧钩子/组件记录按原版本与范围保留。

> **2026-10-15 图片前端接入阶段1：**独立 `codex/image-viewer-business-integration`，从已提交社区e0c1280接入原图片包bd7458a；现有通道/我的→帖子详情已接图片loader钩子、等尺寸预览和独立查看路由，撤销/删除/迟到与返回位置有宿主证据。生产尚无真实图片接口，评论/私信未开发，MIV14仅部分实现。新会话负责帖子图片业务，不编辑社区验收目录/服务/手机；见[阶段1报告](image-viewer-business-stage1-report.md)、[机器记录](image-viewer-business-stage1-verification.json)和[新会话prompt](image-viewer-media-next-session.md)。分析、聚焦34项、其余290项回归、bundle通过；完整Windows回归的SQLite清理errno32已在未改动基线复现，未冒称全套通过。下方历史各按原版本与范围理解。

> **2026-10-15 当前 Android 收尾：**Android10/API29 起默认启用原文件保存，iOS 独立保持关闭。源码提交 `76c35eb`；最终包112＋示例7、两处分析/bundle、ARM64 debug/release构建/验签PASS；S18/API35实际Release20263021真实47项全通过，补齐16MiB编码边界及两份WebP原字节/结算清理。TalkBack按用户确认保留既有人工PASS，不重复。vivo9.4.6.13问题单列播放器兼容，不阻止保存；无仅因过老版本的证据。手机已交回，设置未改、既有ADB未动；见[本轮报告](image-viewer-android-saving-report.md)和[机器证据](image-viewer-android-saving-verification.json)。iOS、其他硬件/版本、业务接入仍各自单列；下方旧日期状态保留历史，不代证当前。

> **2026-10-14 Android本轮收尾：**从d46ccac接续，统一Android10/API29设计并实际提高独立示例minSdk；新增资源边界，修复手机放大旋转丢缩放。最后修改后包108＋示例5、分析/bundle与两份ARM64原生构建/验签PASS，实际S18/API35/APK20263019。45真实codec场景、8幅EXIF、前后台/隐藏、12开关、长图新手势/阅读恢复、TalkBack/大字和原格式保存/竞争取得范围证据；Fossify1.14.0新保存文件回放自动复核PASS。vivo9.4.6.13历史FAIL保留，保存默认关闭；iOS/release与其他硬件/业务仍单列，未取证子项见[本轮报告](image-viewer-android-completion-report.md)和[机器记录](image-viewer-android-completion-verification.json)。手机已交回，设置恢复，既有ADB服务未改；本轮直接普通提交/推送，不发布/部署/main合并。下方保留原版本历史。

> **2026-10-14 相册兼容复验当前：**从已推送 `cdc31289` 接续，组件/示例/锁零改动。用户选择保留原文件，Fossify Gallery 1.14.0 在 vivo S18 上的 SLOW 自动播放、约2秒换帧、两轮结束 PASS，短有限/GIF/无限回放各有范围证据，4份播放后原文件 SHA 一致。vivo 9.4.6.13 无录屏仍失败；静态定位固定100ms调度/未处理有限循环，首开内部触发条件仍未确认。详见[兼容报告](image-viewer-gallery-compatibility-report.md)、[机器证据](image-viewer-gallery-compatibility-verification.json)及台账 currentImageViewerGalleryCompatibility。13:10结束设备操作，撤回新相册媒体权限、停止自有ADB/删除临时密钥。保存默认关闭；旧90＋5/构建证据保留版本，本轮未重跑；完整双端、预算和业务仍未完成。下方为历史记录。

> **2026-10-14 相册身份/时序复试当前：**从已推送1852dda接续，只增带SLOW/FAST、帧号和循环标记的合成对照、示例测试与系统解码诊断点位；核心组件/API/锁/旧素材不变。最后修改后包90＋示例5、两处分析/bundle及两份ARM64 Android构建/验签PASS，实验手机包20263017、普通手机包仍20263014。真实Gal两份原文件SHA/结算清理PASS；vivo Gallery9.4.6.13外部有限首帧启动FAIL，内部切回确认为SLOW自身Frame2/3，但录屏中约0.1–0.2秒换色、超过有限时长仍循环，时序/结束FAIL。相同输入Android系统对照约2秒两轮并结束PASS。旧“会”截图实际GIF，不算WebP通过；文件名/变色不足以判完整回放。具体相册内部缺陷未确认，产品保存仍默认关闭，无转换/降质/fork/生产桥。见[身份报告](image-viewer-gallery-identity-report.md)、[机器证据](image-viewer-gallery-identity-verification.json)及台账currentImageViewerGalleryIdentity。11:11已归还手机/停止私有单设备ADB/删除新密钥，未改系统设置；完整平台矩阵/iOS未验，预算和业务未开发。旧证据保留版本，下方不代证当前。

> **2026-10-14 WebP复试当前：**从已推送 `d7413522` 接续，只增合成回放对照/示例测试与 nativecheckDebug 系统解码诊断，核心组件/API/锁文件不变。最后修改后包90＋示例4、两处分析/bundle与两份ARM64构建/验签PASS。真实 vivo S18：保存字节完整；相册无限WebP无需触碰可播，12秒有限WebP仍首帧静止；同一有限文件在Android系统解码对照可播两轮并结束，问题限定到这版vivo相册有限循环启动/恢复路径，内部具体缺陷未确认。左右切图后播放未确认同文件，不登记通过。产品保存仍默认关闭。相册用20263015、系统解码用20263016，普通手机包保留20263014；旧手势/权限/GIF证据保留各自版本。见[复试报告](image-viewer-webp-retry-report.md)、[机器证据](image-viewer-webp-retry-verification.json)及台账currentImageViewerWebpRetry。手机已交回、私有ADB已停止且两类临时密钥删除；本轮未改系统设置（实读自动旋转1）。上次遗留的本任务公钥本轮已精确清理并更正旧声明。完整平台矩阵/iOS未验，预算/业务未开发；无main合并/Release/部署。

> **2026-10-14 IV01 当前：**真实单台 vivo S18（Android15/API35）已验证。保存提示平分视口的问题已修复，最后修改后包90＋示例3、分析/bundle和两份ARM64 Android构建/验签 PASS，实际APK20263014。原格式PNG/GIF/WebP系统文件逐字节完整、连点/保存中关闭/文件消失与结算清理有真实证据；GIF相册回放限定PASS，**vivo Gallery9.4.6.13直接打开WebP自动回放FAIL，拖动后播放**。产品保存仍默认关闭，完整旋转/后台/读屏矩阵、API24–28权限与iOS未验，MIV13预算和MIV14业务未开发。设置已恢复，独立单设备ADB已停止，手机交回社区。以[单台报告](image-viewer-android-device-report.md)、[机器证据](image-viewer-android-device-verification.json)及台账currentImageViewerAndroid为准；下方旧日期结果保留版本与范围。本分支允许普通提交/推送，不合并main、不发Release、不部署、不接主App。

## 2026-10-13 Android 当前入口

使用 `E:/Hnuhole-image-viewer-component-20261012/repo`，本轮起始 `7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`。上轮宿主实现已审查、提交并正常推送 `3287607cb30887f9df02d2b8dd1cd3fbf3a390cc`；下方2026-10-12“未提交”保留当时快照。当前Android改动、被测摘要和证据见[本轮报告](image-viewer-android-report.md)、[机器记录](image-viewer-android-verification.json)，逐项动作见[验收清单](image-viewer-android-checklist.md)。公共API/输入/终态/回调契约沿用包README与宿主报告。

私有工具/配置/TEMP/Pub/Gradle/日志根为 `E:/Hnuhole-image-viewer-component-20261012/android-20261013`。Flutter3.47.5/Dart3.13.4、JDK17.0.20.1+1、Gradle9.3.1、AGP9.1.0/Kotlin2.4.0、API36/35、build-tools36.0.0、NDK28.2.13676358、WindowsCMake3.22.1。SDK实复制，工具102个包根全在任务内；未升级认证SDK。`run-isolated.ps1` 只允许构建/宿主命令。`run-device.ps1`另要求获准窗口、现有协议41服务、绑定单台实体ID，禁止启动/重启ADB和模拟器。本机助手包含路径常量，跨机器需独立配置。

两个ARM64 APK构建/验签PASS，实际versionCode20263013、minAPI24/target36，新任务签名；独立包 `org.hnuhole.image_viewer_component` 与 `.nativecheck`。`artifacts/hnuhole-viewer-component-debug-arm64-20261013.apk`默认保存关闭，nativecheck包仅双重开关实验启用；hash/版本/完整命令见报告。APK、签名和工具暂保留于Git外供已获准窗口使用，任务结束按明确归属清理；不清理共用环境或复制认证签名。

最终包88、示例3、两处分析和bundle本轮PASS，与最终APK使用同一包摘要，两份锁文件不变。用户授予vivo S18窗口并可人工核对，暂不限定，社区需要即停；授权后ADB列表为空，Windows未见vivo/Android/MTP接口，实际系统/API/ABI未读取，未安装/触摸/访问相册。连接后锁定唯一获准实体ID，核对兼容性、APK版本和已有包归属再执行清单；不能把窗口获准写成设备通过，不重启ADB或盲目装驱动解决连接。

iOS缺独立Mac/Xcode/设备及受控保存实验入口，Android flavor不能当iOS scheme。MIV13手机预算未开发/固定，MIV14业务接入未开发，双端/M3/M4未完成。以下保留旧日期交接。

## 2026-10-12 当前独立组件交接

先读 [本轮报告](image-viewer-component-host-report.md)、[本轮记录](image-viewer-component-host-verification.json)、[包 README](../../packages/image_viewer/README.md) 及台账 currentImageViewerComponent。起始 SHA 与最终 HEAD 均为 `7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`；源码修改未提交，只在 `E:/Hnuhole-image-viewer-component-20261012/repo`。另一台机器仅 clone 远端不会取得本轮未提交实现，需要先转移本工作区的源码变更或等待另行授权发布，不能把现有远端 M1 视为新组件。

默认 main 启动 ComponentApp，原 M1 独立入口 runM1Probe 保留。公共契约、完整原格式保存、关闭归属和迟到隔离见包 README；onClosed 由调用方处理导航，controller/saver 由调用方 dispose。原生 adapter 默认为空，保存实验仅显式 VIEWER_ENABLE_NATIVE_EXPORT 开启。

本机执行只使用实复制的独立 Flutter/Pub/最小 Android SDK，SDK bin/cache、用户配置、TEMP 与日志均任务内。启动器为 `E:/Hnuhole-image-viewer-component-20261012/run-flutter.ps1`，可执行的 Flutter 命令只限严格离线 pub get、分析、宿主测试和 bundle，禁原生构建/设备/下载。任务自有缓存清理状态见本轮记录；清理后复验必须重新准备独立工具，不运行认证 SDK。

本轮自有工具副本和生成缓存现已清理，日志/源码仍保留。复验时先创建新任务私有目录，准备 Flutter 3.47.5／Dart 3.13.4 和锁文件所需离线 Pub；若实复制现成 SDK，必须确认无硬/软链接，并把 SDK 工具自身的 `.dart_tool/package_config.json` 绝对路径重定位到私有根，再核对 `bin/cache` 与所有 package roots 没有指向认证/共享目录。`run-flutter.ps1` 的根路径常量要指向新私有目录；只读核对后才执行上述命令。缺少必要依赖时记录阻塞，不默认自动安装完整工具链。

在已确认不会与认证冲突的独立工具终端执行：

```text
# packages/image_viewer
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --machine --concurrency=1
# packages/image_viewer/example
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --machine --concurrency=1 test/component_example_test.dart
flutter build bundle --debug --no-pub
```

缺离线依赖/SDK artifact 时记录 BLOCKED，不能转而复用认证写入缓存或自动安装工具链。两份锁文件 hash 见本轮记录，不能删除/升级。

专用 Android SDK/JDK/Gradle 环境和独立 Mac/Xcode 准备好后才分别构建 apk/ios，实际命令与版本门槛见本轮报告。本轮最小 Android SDK 只供 bundle 寻址，不能当原生可构建环境。专用且另行授权设备上运行 `integration_test/image_viewer_component_device_test.dart`；原生导出需操作者和相册核对，再显式 `--dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true`。旧 M1设备入口及 M1_EXPORT_FIXTURES 不代证当前组件。

每端分别补：真实触摸/长图回顶全过程与新下拉、旋转/多指/读屏/大字、安全区、快速切页及真实前后台；系统权限允许/拒绝/撤销/首次授权引起的 inactive/resumed、重复点击及保存/关闭竞争；原始导出文件 SHA/帧时长/循环；系统目标相册实际 GIF/WebP 回放。插件成功、完整文件、相册实际播放分开记录。gal iOS 文件导入强制解包风险待核对，不能用替身关闭；条件 GIF 未批准/未启用。MIV13 手机上限/预算与 MIV14 三类业务接入尚未开发/固定。

本轮未使用设备、ADB、模拟器、认证服务/数据库/密钥/账号。M1平台关、M3正式双端验收及M4仍未完成。下面完整保留2026-10-10的历史接续记录；其中36项和旧提交/清理授权不描述本轮。

## 2026-10-10 历史 M1 交接
2026-10-10。GitHub分支：codex/image-viewer-component。首先阅读 [M1报告](image-viewer-m1-report.md)、[现行计划](image-viewer-component-plan.md)和台账 IV01。本次实际完成的是 M1 宿主技术样例，36项宿主测试通过；Android/iOS 原生构建与手机技术关未通过。M2/M3/M4尚未开始。

## 获取分支
新电脑在准备存放项目的目录执行：
```powershell
git clone --branch codex/image-viewer-component --single-branch https://github.com/zewbby/HnuHole.git HnuHole-image-viewer
Set-Location HnuHole-image-viewer
git branch --show-current
git log -1 --oneline
git status --short
```
预期分支名 codex/image-viewer-component，工作区干净。若已有该仓库且有未提交改动，先保留或建立独立worktree，不强制reset，不覆盖匿名/文字社区工作。

## 复现本机检查（不需要手机）
实际被测工具是 Flutter3.47.5/Dart3.13.4。先 flutter --version；版本不同须单列复验，不能沿用本次PASS。不复制已删除的本机缓存；两份锁文件和所有fixture均已提交。

Windows PowerShell：
```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = Join-Path $env:LOCALAPPDATA 'HnuHole-image-viewer-pub-cache'
Set-Location packages/image_viewer
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
Set-Location example
flutter pub get
flutter analyze --no-pub
flutter build bundle --debug --no-pub
git diff -- pubspec.lock ../pubspec.lock
```
预期：两个analyze无问题；36项测试通过；bundle成功；锁文件无版本/来源漂移。保留原image-viewer-m1-*证据，新版本/新设备生成新的记录，不覆盖成旧版本已通过。

Mac/Linux Bash（先从仓库根开始）：
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_CACHE="$HOME/.cache/hnuhole-image-viewer-pub"
cd packages/image_viewer
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
cd example
flutter pub get
flutter analyze --no-pub
flutter build bundle --debug --no-pub
```
Pillow只在重生成fixture时需要；本次使用12.3.0，现有图片可以直接测试。Python结果收集和Dart量测命令见包README。资源数据仅桌面样本，不能当手机预算。

## 下一步平台构建与M1验收
独立示例 Android applicationId：org.hnuhole.image_viewer_m1，iOS bundleId：org.hnuhole.imageViewerM1。不要覆盖原 HnuHole 匿名验收App。Android Gradle9.3.1/AGP9.1.0/Kotlin2.4.0 缓存本机没有建立；下一台具备工具链再构建。iOS需要Mac/Xcode及签名配置。

在 example 中：
```text
flutter build apk --debug --no-pub
flutter build ios --debug --no-codesign --no-pub
flutter test integration_test/image_viewer_device_test.dart -d <专用设备ID>
```
第一条仅Android，第二条仅Mac/iOS。第三条默认只做严格长图技术场景；保存测试默认SKIP，需明确安排设备操作者和相册核对后使用：
```text
flutter test integration_test/image_viewer_device_test.dart -d <专用设备ID> --dart-define=M1_EXPORT_FIXTURES=true
```
该选项会主动导出本任务GIF/WebP合成图片并可能触发系统权限对话框；插件返回成功也不是相册动画回放PASS。

需分别记录 Android、iPhone 的设备/系统/App源码SHA及以下结果：
1. 普通图/长图/多图真实触摸：适宽顶部、回顶同手势没有退出动画、全部松手后新下拉、双指/双击/取消、缩放不误切图、首尾。
2. GIF和动态WebP：连续切图、实际前后台、关闭和访问失效后非当前图片停止；反复开关，无迟到界面污染。
3. 原文件保存：允许/禁止、拒绝/撤销权限、重复点击、保存中关闭/失效、空间或格式失败；输出文件SHA/帧数/时长/循环与原始来源核对。
4. 系统相册回放：GIF和动态WebP分别在目标相册实际播放；记录照片可导入、文件动画完整和相册回放三种证据，不能只看缩略图。
5. 核对 gal iOS 文件导入强制解包风险；必要时比较公开字节API，不能靠Dart替身推断不会崩溃。
6. 只有原格式实际不满足目标相册时才评估兼容。工具中二值透明、循环与时序适配已试验；半透明默认拒绝。兼容质量、手机峰值/耗时/体积和提示语需具体决定，未批准默认转换。

M1退出条件仍需双端技术证据。M2统一接口、错误来源/重试/稳定ID阅读状态、旋转、正式UI/读屏/大字与受保护来源隔离尚未实现；M3正式验收、M4三类业务接入不可记为仅差设备测试。按AGENTS同步四份交接文档与IV01/MIV记录。

## 本机清理边界
只删除本次自有 D:/zewbbyTest/Hnuhole-image-viewer-m1-20261010 缓存和 packages/image_viewer 下本次生成的 build/.dart_tool、本机插件/平台配置。保留现成Flutter/Android/JDK、其他pub/Gradle缓存、AVD、用户数据、其他工作树。实际结果见 image-viewer-m1-verification.json 的 cleanup。下次运行先pub get，Android必要时重新生成被gitignore忽略的wrapper启动文件。


2026-10-10 交付记录：M1源码与交接已推送到 `codex/image-viewer-component`，源码提交 `c500788fa99a571cb67f8c4a663e9e4da2c11411`，已核对远端SHA。后续交接元数据提交以远端分支最新HEAD为准。缓存删除被自动审批检查拒绝（blocked by policy），未执行删除；本任务5个缓存/构建目录共253787594字节仍保留。准确路径和状态见 `image-viewer-m1-cleanup.json`；源码、锁文件和合成测试图片已入库，换机不依赖这些缓存。M1平台关卡仍待执行，正式组件尚未验收。
