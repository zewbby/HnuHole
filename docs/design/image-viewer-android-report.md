# IV01 Android 构建与单台设备记录（2026-10-13）

> **2026-10-14 相册兼容复验当前：**从已推送 `cdc31289` 接续，组件/示例/锁零改动。用户选择保留原文件，Fossify Gallery 1.14.0 在 vivo S18 上的 SLOW 自动播放、约2秒换帧、两轮结束 PASS，短有限/GIF/无限回放各有范围证据，4份播放后原文件 SHA 一致。vivo 9.4.6.13 无录屏仍失败；静态定位固定100ms调度/未处理有限循环，首开内部触发条件仍未确认。详见[兼容报告](image-viewer-gallery-compatibility-report.md)、[机器证据](image-viewer-gallery-compatibility-verification.json)及台账 currentImageViewerGalleryCompatibility。13:10结束设备操作，撤回新相册媒体权限、停止自有ADB/删除临时密钥。保存默认关闭；旧90＋5/构建证据保留版本，本轮未重跑；完整双端、预算和业务仍未完成。下方为历史记录。

> **2026-10-14 相册身份/时序复试当前：**从已推送1852dda接续，只增带SLOW/FAST、帧号和循环标记的合成对照、示例测试与系统解码诊断点位；核心组件/API/锁/旧素材不变。最后修改后包90＋示例5、两处分析/bundle及两份ARM64 Android构建/验签PASS，实验手机包20263017、普通手机包仍20263014。真实Gal两份原文件SHA/结算清理PASS；vivo Gallery9.4.6.13外部有限首帧启动FAIL，内部切回确认为SLOW自身Frame2/3，但录屏中约0.1–0.2秒换色、超过有限时长仍循环，时序/结束FAIL。相同输入Android系统对照约2秒两轮并结束PASS。旧“会”截图实际GIF，不算WebP通过；文件名/变色不足以判完整回放。具体相册内部缺陷未确认，产品保存仍默认关闭，无转换/降质/fork/生产桥。见[身份报告](image-viewer-gallery-identity-report.md)、[机器证据](image-viewer-gallery-identity-verification.json)及台账currentImageViewerGalleryIdentity。11:11已归还手机/停止私有单设备ADB/删除新密钥，未改系统设置；完整平台矩阵/iOS未验，预算和业务未开发。旧证据保留版本，下方不代证当前。

> **2026-10-14 WebP复试当前：**从已推送 `d7413522` 接续，只增合成回放对照/示例测试与 nativecheckDebug 系统解码诊断，核心组件/API/锁文件不变。最后修改后包90＋示例4、两处分析/bundle与两份ARM64构建/验签PASS。真实 vivo S18：保存字节完整；相册无限WebP无需触碰可播，12秒有限WebP仍首帧静止；同一有限文件在Android系统解码对照可播两轮并结束，问题限定到这版vivo相册有限循环启动/恢复路径，内部具体缺陷未确认。左右切图后播放未确认同文件，不登记通过。产品保存仍默认关闭。相册用20263015、系统解码用20263016，普通手机包保留20263014；旧手势/权限/GIF证据保留各自版本。见[复试报告](image-viewer-webp-retry-report.md)、[机器证据](image-viewer-webp-retry-verification.json)及台账currentImageViewerWebpRetry。手机已交回、私有ADB已停止且两类临时密钥删除；本轮未改系统设置（实读自动旋转1）。上次遗留的本任务公钥本轮已精确清理并更正旧声明。完整平台矩阵/iOS未验，预算/业务未开发；无main合并/Release/部署。

> **2026-10-14 IV01 当前：**真实单台 vivo S18（Android15/API35）已验证。保存提示平分视口的问题已修复，最后修改后包90＋示例3、分析/bundle和两份ARM64 Android构建/验签 PASS，实际APK20263014。原格式PNG/GIF/WebP系统文件逐字节完整、连点/保存中关闭/文件消失与结算清理有真实证据；GIF相册回放限定PASS，**vivo Gallery9.4.6.13直接打开WebP自动回放FAIL，拖动后播放**。产品保存仍默认关闭，完整旋转/后台/读屏矩阵、API24–28权限与iOS未验，MIV13预算和MIV14业务未开发。设置已恢复，独立单设备ADB已停止，手机交回社区。以[单台报告](image-viewer-android-device-report.md)、[机器证据](image-viewer-android-device-verification.json)及台账currentImageViewerAndroid为准；下方旧日期结果保留版本与范围。本分支允许普通提交/推送，不合并main、不发Release、不部署、不接主App。

本轮保存既有宿主成果并完成独立示例 Android 原生构建。组件核心封装未重做，主 App、认证、Go/SQL、上传及业务接口未修改。单台手机窗口已获用户授权：现在可用、可配合人工核对，暂不限定，社区需要时立即停止。截至本记录建立时，ADB 连接列表为空；用户指定 vivo S18，尚不能读取其实际系统/ABI或安装 APK。构建和宿主 PASS 不代表真机通过。后续设备结果按[验收清单](image-viewer-android-checklist.md)登记。

## Git 与被测版本

- 工作目录：`E:/Hnuhole-image-viewer-component-20261012/repo`，分支 `codex/image-viewer-component`。
- 本轮起始 HEAD/实际远端：`7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`。
- 26 个既有修改经范围、秘密/账号材料、缓存及制品排除审查后保存为 `3287607cb30887f9df02d2b8dd1cd3fbf3a390cc`，已正常推送并核对远端一致。
- origin：`https://github.com/zewbby/HnuHole.git`；未强推、合并 main、发布 Release 或部署。
- 下列最终 APK/宿主命令执行时 HEAD 为上述保存提交，Android 示例修改尚未提交；整个包实际工作区文件 SHA256 摘要为 `23f2978ef52e94194f564fbdd0bf63cd21a218c68e598a231ab893fd8075aec0`，命令前后稳定。精确文件摘要在本机命令 JSON 内。
- 历史 2026-10-12 宿主报告保留当时版本、88+2 及未提交快照；本轮结果单列，不改写旧证据。

## 独立环境与构建缺口

本轮工具、用户目录、TEMP、Pub、Gradle 及日志均位于 `E:/Hnuhole-image-viewer-component-20261012/android-20261013`。实复制已有 Flutter 3.47.5/Dart 3.13.4、Microsoft JDK 17.0.20.1+1、Android API36/build-tools36.0.0/NDK28.2.13676358 和公开依赖缓存；没有升级/清理认证共享 SDK。Flutter 工具包的 102 个 package roots 已重定位至本任务，SDK `bin/cache` 写入独立副本。Gradle 单次 daemon、最多 2 workers、JVM 2GB，自动 SDK/JDK 下载关闭。

初次 Gradle 下载未进入编译，all 包中断后采用同版本 9.3.1 bin 包；两次停滞仅停止已核对为本任务的 wrapper Java 进程，没有停止其他服务。下载 bin 为 137037885 字节，经官方 SHA256 `b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06` 校验后使用；其中一次恢复下载使用公开镜像，执行包仍与官方摘要逐字节一致。AGP9.1.0/Kotlin2.4.0 保留锁定版本。

首轮真正编译失败于锁定的 jni1.1.0 `compileDebugJavaWithJavac` 缺 android-35。准确补齐 API35（64273788 字节）及 Windows CMake3.22.1（16116742 字节），仅下载至 E 并核对 Google repository 元数据摘要；未安装 Android Studio/完整工具链，没有新自研 JNI 桥。复验成功。SDK XML reader 警告保留于日志，最终 exitCode=0。最初非 split APK 的静态 ABI 广告包含其他 ABI，而 Flutter engine 只有 ARM64，因此改用 Flutter 标准 `--split-per-abi`；最终 APK 广告与实际原生库均仅 ARM64，此项不是已发生的设备故障。

环境与失败记录：本机 `logs/private-tool-isolation.json`、`gradle-verified-download.json`、`required-sdk-parts.json`、`android-component-cached-gradle-build.log/.json`；中断记录单列，不能登记构建通过。原共享工具仅只读/复制；签名使用本任务新生成的 `profile/.android/debug.keystore`，未复制认证签名或 ADB 密钥。

## 本轮实际宿主检查

命令均使用本轮 `run-isolated.ps1` 和私有 Flutter，离线 get 保留两份锁文件。下表是最终示例修改之后实际执行的检查，日志根目录为 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs`，每条另有同名 `.json` 保存命令、时间、exitCode、源码摘要及锁文件摘要。

| 工作目录 | 实际命令 | 结果 | 日志 |
|---|---|---|---|
| packages/image_viewer | flutter analyze --no-pub | PASS，No issues | package-analyze-final.log |
| packages/image_viewer | flutter test --no-pub test | PASS，88 项 | package-host-tests-final.log |
| packages/image_viewer/example | flutter analyze --no-pub | PASS，No issues | example-analyze-final.log |
| packages/image_viewer/example | flutter test --no-pub test | PASS，3 项 | example-host-tests-final.log |
| packages/image_viewer/example | flutter build bundle --debug --no-pub | PASS | example-bundle-final.log |

新增示例迟到来源用例第一次失败是测试未 pump 新路由首帧导致查找不到查看器；修正测试调度，再加强为关闭旧来源后打开不同 ID 的长图，最终 3 项通过。没有把测试调度问题归为设备/原生问题。

锁文件 SHA256 保持：包 `00ac99d693f003b46111d24e18a233741aedfd3501569130d57d731ca192fb81`；示例 `9a7de0b094b07456d44016212168f2f5890e5a74d0bf4f708d77db6c51c95a24`。

## 最终 Android APK

两条命令在 `packages/image_viewer/example` 实际完成，最终日志分别为 `android-component-arm64-final.log/.json` 与 `android-nativecheck-arm64-final.log/.json`：

```text
flutter build apk --debug --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-platform20261013 --build-number=20261013
flutter build apk --debug --no-pub --flavor=nativecheck --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-platform20261013 --build-number=20261013 --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
```

| 字段 | component | nativecheck |
|---|---|---|
| 原生构建 | PASS | PASS |
| 包名 | org.hnuhole.image_viewer_component | org.hnuhole.image_viewer_component.nativecheck |
| 实际 versionName | 0.0.0-platform20261013 | 0.0.0-platform20261013-nativecheck |
| 实际 versionCode | 20263013 | 20263013 |
| 最低/目标 API | 24 / 36 | 24 / 36 |
| ABI | arm64-v8a | arm64-v8a |
| 文件大小 | 82169803 字节 | 82170187 字节 |
| 原生保存 | 默认关闭 | 双重显式开关，仅平台实验 |
| APK SHA256 | 3f76623695dd50f476b7823a7b97bced5cfd1b95b8c692cd8661d89e9a0fb28c | 277445b583d40a8090d69e500f1413c9d0fff071a194af8b7ab97e34a0e07fea |

Flutter ABI split 对请求 build-number 加 2000，实际安装版本以 APK 元数据为准。`aapt dump badging` 与 `apksigner verify --verbose --print-certs` 均已执行；两个 APK v2 签名验证 PASS，证书 SHA256 `77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5`。检查日志为 `component-arm64-badging-final`、`component-arm64-signature-final` 及对应 nativecheck 名称；`final-apk-files.json` 记录实际库、大小及复制路径。

APK 保留于任务外部 `android-20261013/artifacts/hnuhole-viewer-{component,nativecheck}-debug-arm64-20261013.apk`，等待本窗口使用，不入 Git。独立包名和新签名不会覆盖主 App/认证 App。

## 单台设备阶段（进行中）

用户指定 vivo S18 并授予窗口。现有 ADB 服务协议 41 与私有 public client37.0.1 匹配，未重启服务；授权后仅查询连接列表/Windows USB 状态。当前连接列表为空，未见 vivo/Android/MTP 接口，未安装 App、执行触摸、修改设置或访问相册。实际设备 ID、Android/API/ABI、系统相册包/版本、字体与 TalkBack 状态尚待读取/操作者核对。

AV01–AV10、AS01–AS08 当前均 NOT_RUN，逐项待验条件/人工动作/素材 SHA 见清单。保存成功回调、输出文件完整性、系统相册实际回放分别登记。API29+ 的该 Gal 写入路径不请求旧存储权限，拒绝场景若不适用应 SKIP，保留 API24–28 未验。示例故障注入为 3 秒来源延迟、2 秒真实 Gal 调用前适配延迟及自有临时文件删除，不将其冒称为系统随机故障或原生性能测量。

## 未关闭门槛与复验

- Android：连接获准的单台 ARM64/API24+ 实体设备后先核对版本、包是否已存在及 APK 摘要，限定 `-s <ID>` 操作；不使用默认设备发现安装、不操作模拟器、不重启 ADB。随后先 component 查看交互，再 nativecheck 保存实验，逐项记录失败和人工证据。社区要求用机即停止。
- iOS：无独立 Mac/Xcode/iOS 设备；原生构建、Photos/权限、系统相册回放、VoiceOver/真机均 NOT_RUN。当前 Android flavor 不是 iOS scheme；需先准备独立受控 iOS 保存实验入口，再执行 `flutter build ios --debug --no-codesign --no-pub` 和经授权的设备步骤；不能直接照搬 nativecheck flavor 冒称可运行。
- MIV13：手机资源预算和明确支持上限尚未开发/固定，本轮小型素材/编译结果不能代证。
- MIV14：三类业务接入尚未开发，本轮不接主 App。
- 产品原生保存默认保持关闭，完整双端/M3/M4未验收。本轮不发布 Release、不部署、不合并 main。
