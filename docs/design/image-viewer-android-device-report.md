# IV01 单台 Android 实测与保存反馈修复（2026-10-14）

> **2026-10-14 相册兼容复验当前：**从已推送 `cdc31289` 接续，组件/示例/锁零改动。用户选择保留原文件，Fossify Gallery 1.14.0 在 vivo S18 上的 SLOW 自动播放、约2秒换帧、两轮结束 PASS，短有限/GIF/无限回放各有范围证据，4份播放后原文件 SHA 一致。vivo 9.4.6.13 无录屏仍失败；静态定位固定100ms调度/未处理有限循环，首开内部触发条件仍未确认。详见[兼容报告](image-viewer-gallery-compatibility-report.md)、[机器证据](image-viewer-gallery-compatibility-verification.json)及台账 currentImageViewerGalleryCompatibility。13:10结束设备操作，撤回新相册媒体权限、停止自有ADB/删除临时密钥。保存默认关闭；旧90＋5/构建证据保留版本，本轮未重跑；完整双端、预算和业务仍未完成。下方为历史记录。

> **2026-10-14 WebP复试当前：**从已推送 `d7413522` 接续，只增合成回放对照/示例测试与 nativecheckDebug 系统解码诊断，核心组件/API/锁文件不变。最后修改后包90＋示例4、两处分析/bundle与两份ARM64构建/验签PASS。真实 vivo S18：保存字节完整；相册无限WebP无需触碰可播，12秒有限WebP仍首帧静止；同一有限文件在Android系统解码对照可播两轮并结束，问题限定到这版vivo相册有限循环启动/恢复路径，内部具体缺陷未确认。左右切图后播放未确认同文件，不登记通过。产品保存仍默认关闭。相册用20263015、系统解码用20263016，普通手机包保留20263014；旧手势/权限/GIF证据保留各自版本。见[复试报告](image-viewer-webp-retry-report.md)、[机器证据](image-viewer-webp-retry-verification.json)及台账currentImageViewerWebpRetry。手机已交回、私有ADB已停止且两类临时密钥删除；本轮未改系统设置（实读自动旋转1）。上次遗留的本任务公钥本轮已精确清理并更正旧声明。完整平台矩阵/iOS未验，预算/业务未开发；无main合并/Release/部署。

> **复试澄清：**下方原“拖动后PASS”只保留操作者当时看到动画的报告；没有确认拖动后仍为该有限WebP，不能作为同文件播放通过。下方密钥收尾对应旧声明亦需更正：旧回执实际为私钥已删、公钥未删，遗留公钥在本次复试开始已精确删除。旧版本测试与原始回执保留；本轮细分结果和更正见新复试报告。

本轮完成保存反馈布局修复、重跑宿主检查、两份 Android APK 构建与实际单台验证。**原文件保存完整性通过；vivo 系统相册直接打开动态 WebP 的自动回放失败，拖动后会播放。原生保存产品默认继续关闭。**未宣布完整 Android、双端或 M3/M4 通过。

机器证据见 [device-verification](image-viewer-android-device-verification.json)，逐项入口见 [清单](image-viewer-android-checklist.md)。2026-10-13 [构建报告](image-viewer-android-report.md)和原机器记录保留原日期、APK 与范围；下列结果不回写成旧版本通过。

## 版本、范围与公共契约

工作区 `E:/Hnuhole-image-viewer-component-20261012/repo`，分支 `codex/image-viewer-component`，origin `https://github.com/zewbby/HnuHole.git`。本阶段实际起点 `7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`；宿主成果已审查保存并正常推送 `3287607cb30887f9df02d2b8dd1cd3fbf3a390cc`，Android 准备已正常推送 `a20e5cfad5f469dd44b8de80add14aa37a4af7e0`。本次测试执行时 HEAD 为 `a20e5cf`，修复尚在工作区；本记录所属提交保存修复与证据，最终提交/远端见 Git 和任务外 `logs/final-publication-receipt.json`，不使用自引用提交哈希。

唯一运行时代码修改为 `packages/image_viewer/lib/src/viewer.dart` 的保存提示布局；新增两个回归在 `test/viewer_contract_test.dart`。其余修改限 IV01 交接/台账。没有重做封装或修改主 App、认证、Go/SQL、上传/业务接口、依赖版本或锁文件。

公共 API 沿用 [包 README](../../packages/image_viewer/README.md)：`ViewerItem`/`ViewerSource`/`ViewerController`/`HnuImageViewer`/`ViewerSaveCoordinator`。调用方提供有序图片组、稳定唯一 ID、实际尺寸、获准来源和可选完整原文件能力；不接收账号、Bearer、密码或恢复材料。关闭、撤销或卸载为会话终态，旧来源/解码/保存反馈由代次隔离；调用方负责导航与 dispose。已经进入保存适配器的系统写入不承诺取消。组件不建立长期私有图片缓存。

extended_image、Flutter 和 gal 继续提供底层能力。长图适宽从顶进入、同一次回顶手势不得退出、全部松手后新的下拉才允许关闭；动画与保存保留原格式，没有 GIF 转换、静默降质、引擎/解码器 fork 或新增原生桥。

## 实际问题与修复

首次真实 PNG 保存成功后，底部提示的 `Flexible` 和图片的 `Expanded` 平分可用高度。短提示留下大量空白，图片视口约减半，切图按钮被抬到中部。手机截图 `as02-original-save-feedback.png` 与新增宿主回归均实际复现：400×600 场景按钮底边从 600 移到 384。

改为按本组件实际约束限制提示高度：短提示占自身高度，大字最多占四分之一并可滚动；保留 liveRegion。两个回归覆盖 400×600/1倍文字和 320×240/3倍文字，断言视口、底部按钮、读屏提示与切图后清除反馈。旧代码两个失败；修复后曾因测试自身 SemanticsHandle 释放及已弃用断言 API 再失败，已分别修正，最后一次受影响修改后完整检查通过。

手机修复版再次实际保存 PNG，`as02-fixed-before-save.png`/`as02-fixed-after-save.png` 显示视口正常、底部按钮不再上移；新媒体原文件与合成素材逐字节一致。

## 最后修改后的实际检查与 APK

日志根：`E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs`。命令使用同根 `run-isolated.ps1` 和实复制的 E 盘 Flutter/Android SDK/JDK、Pub/Gradle/TEMP。未执行认证共用 SDK，未升级/清理它，未向 C 下载大型缓存。工具版本/下载缺口及原生失败修复保留在上一构建报告。本次无工具链升级或追加下载。

以下七项均 exitCode=0、执行前后源码一致，完整包 manifest 摘要 **`47386959e21399ea6d951acda3b7b5fd94855a2f712abedab62328cf632d426b`**。每条同名 JSON 保存实际命令、时间、HEAD、manifest 与锁摘要；旧通过不代证本次。

| 目录 | 实际命令 | 结果 | 日志名（.log/.json） |
|---|---|---|---|
| packages/image_viewer | flutter analyze --no-pub | PASS，无问题 | package-analyze-layout-verified |
| packages/image_viewer | flutter test --no-pub | PASS，90 项 | package-host-tests-layout-verified |
| example | flutter analyze --no-pub | PASS，无问题 | example-analyze-layout-verified |
| example | flutter test --no-pub test | PASS，3 项 | example-host-tests-layout-verified |
| example | flutter build bundle --debug --no-pub | PASS | example-bundle-layout-verified |
| example | 下方 component 命令 | 原生构建 PASS | android-component-layout-final |
| example | 下方 nativecheck 命令 | 原生构建 PASS | android-nativecheck-layout-final |

```text
flutter build apk --debug --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-platform20261014 --build-number=20261014
flutter build apk --debug --no-pub --flavor=nativecheck --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-platform20261014 --build-number=20261014 --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
```

锁文件未删除或升级。包锁 SHA256 `00ac99d693f003b46111d24e18a233741aedfd3501569130d57d731ca192fb81`；示例锁 `9a7de0b094b07456d44016212168f2f5890e5a74d0bf4f708d77db6c51c95a24`。

| 当前 APK | component | nativecheck |
|---|---|---|
| 包名 | org.hnuhole.image_viewer_component | org.hnuhole.image_viewer_component.nativecheck |
| versionName | 0.0.0-platform20261014 | 0.0.0-platform20261014-nativecheck |
| 实际 versionCode | 20263014 | 20263014 |
| 大小 | 82170311 字节 | 82170687 字节 |
| SHA256 | 51c9950f9b723aed012e3b6f08d8232197c67d5445dbc1e52ac2e556779b0e61 | 6c7ad141a519b20adc713cbac000cc87a127f784ef9d93f519e5c9ea8ba3817c |
| 保存 | 默认关闭 | flavor+define 双重实验开关 |

两份实际仅 ARM64、minAPI24/target36；aapt 元数据与 v2 验签 PASS。任务新测试证书 SHA256 `77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5`，没有复用认证秘密。APK 位于任务外 `android-20261013/artifacts/hnuhole-viewer-{component,nativecheck}-debug-arm64-20261014.apk`，不入 Git。手机安装版本也实际核对为上述版本。首次 nativecheck 更新被系统拒绝（INSTALL_FAILED_ABORTED），用户确认后原地更新成功，没有采用自动卸载回退。

## 实际设备与逐项结果

单台实体 **vivo S18/V2323A，Android15/API35，arm64-v8a**；实际绑定序列号仅任务外私有记录，公开证据使用摘要。用户窗口“暂不限定，社区需要时立即停止”，允许人工核对。系统相册 `com.vivo.gallery` 当前 **9.4.6.13 / 9040613**（dump 中另一 9.3.24.0 为系统回退包）；TalkBack 当前 **17.0.1.926549743 / 60215178**，已实际读到开启服务。

AV02/AV03/AV04 人工证据来自实际 `20263013` APK；保留各自版本，不冒称在 `20263014` 全部重跑。本次只改保存提示布局，手势源码未改；当前 APK 的阅读、返回、来源、动画、保存及基础读屏另有实际记录。原 Android integration 为真实手机运行 **2 PASS＋1 SKIP**，但使用 Flutter tester 注入手势，原生保存被跳过，不能作为手指或相册证据。runner 初次安装被拒绝后曾自行重装本任务自己的 component 包，随后已恢复验签的人工 APK；未触其他 App。

下表“部分”表示列出的子项通过，但完整矩阵仍登记 NOT_RUN；精确子项/版本/原始文件见机器证据。

| 项 | 实际结果与限制 |
|---|---|
| AV01 初始显示 | PASS，普通适屏、长图适宽从 TOP 进入，正常包保存禁用 |
| AV02 缩放/多指 | 人工限定 PASS：捏合、平移、单指变双指、双击，答复“一切OK”；完整触摸矩阵未验 |
| AV03 同手势回顶 | 严格复验 PASS：阅读位置回顶同手势不退出、全部松手后新下拉退出，人工“一切正常”＋录像/返回首页。最初录像仅从顶下拉，不计严格序列通过 |
| AV04 旋转 | 部分：BAND03 适宽状态横屏再竖屏 PASS；放大/手势进行中的旋转 NOT_RUN |
| AV05 阅读恢复 | PASS，ADB 在实际手机操作：BAND05/06/07 切到 GIF 再返回，视口像素完全一致；新会话从 TOP 进入。其余缩放组矩阵未验 |
| AV06 退出 | 限定 PASS，系统返回、关闭按钮各回到本示例首页；合格物理下拉见 AV03。快速反复开关完整矩阵未验 |
| AV07 来源/撤销 | PASS，实际故障入口先失败、点击重试恢复、撤销回到调用方；仅合成来源，未使用业务网络 |
| AV08 迟到来源 | PASS，三秒来源未结算即关闭，立即打开不同长图；之后仍是 2/4 TOP，无旧反馈/错误。应用 PID 限定日志未见卸载回调异常 |
| AV09 动画/生命周期 | 部分：当前 GIF/WebP 前台实际录像均出现红绿蓝连续帧 PASS；OS 后台/不可见停播、资源矩阵 NOT_RUN，宿主监听数量不代证 |
| AV10 大字/读屏 | 部分：系统最大字体 1.88，按钮/图序可见并切图 PASS；TalkBack 直接触摸下载读禁用说明、双击下一张 PASS。初次右滑未找到保存说明的反馈保留；完整反馈朗读/横屏组合未验 |
| AS01 权限 | API35 hasAccess=true、无旧存储请求；该拒绝分支 SKIP。API24–28 拒绝/再授权/权限对话 lease 未验 |
| AS02 PNG | PASS，真实写入、新项、原始字节与实际相册 PNG 显示；保存提示布局修复后手机复验 PASS |
| AS03 GIF | 限定 PASS，934字节原文件完整，人工看到系统相册颜色切换；完整 GIF 矩阵未验 |
| AS04 WebP | **FAIL：直接打开自动回放**；290字节原文件完整 PASS，人工拖动后连续播放 PASS |
| AS05 连点 | PASS，注入两秒适配器延迟内三次点按，忙态禁用，只有一次真实派发和一项完整 GIF |
| AS06 保存中关闭 | PASS，关闭后真实 Gal 写入仍成功，新图无旧反馈，GIF 完整且结算后清理；不宣称原生写入已取消 |
| AS07 文件消失 | 限定 PASS，两次故意删除自有文件后真实 Gal 失败，忙态恢复可重试，无多余媒体；插件返回 notSupportedFormat，文案为格式错误，精确“文件消失”诊断未改造 |
| AS08 清理 | PASS，当前五次真实成功＋两次真实失败均观察文件/目录不存在；保存中关闭仍能完成系统写入，未提前删除正在使用的文件 |

三类输出及竞争样本均取回**确切自有 URI**，与仓库素材逐字节一致；当前本任务相册新项共六个（含修复前 PNG）。实际文件 SHA/长度/owner/URI 在记录中；原始字节一致证明帧/时序/循环数据未被转换，播放器表现单列。有限动画结束后静止是预期，WebP 问题为首次打开停在首帧、拖动后才开始播放。

所有原始截图、录像、PID 限定日志留在任务外，不提交真实设备序列号、VM 服务 token、密钥、缓存或 APK。系统相册自身出现的邻近缩略图条仅存在私有本地录像，未查询/导出那些原文件，也未提交/发布录像。

## WebP 最小复现与影响范围

最小文件为仓库 `example/assets/fixtures/animation.webp`：96×72、290字节、3帧、80/120/200ms、rawLoop2，SHA256 `8b8b45e3f971e60b42ff0d45cc01aada69ff7856744500dfb655930595bfa139`。真实 Gal 写入 owner=`org.hnuhole.image_viewer_component.nativecheck`、MIME=`image/webp` 的 MediaStore 项；取回 SHA 完全相同。

在上述 vivo Gallery 用 ACTION_VIEW 打开该确切 URI，首帧静止；人工拖动后自动连续切换。`webp-system-gallery-replay-recording.json`/原始短视频记录直接打开静止，人工两次反馈记录在 `as04-gallery-operator-result.json`。当前组件自身的 Android 前台 WebP 已通过实际录像，不能把相册问题扩展成 Gal 字节损坏或 Flutter/extended_image 动画均失败；其他手机、其他相册入口/版本未验。

当前替代安排为保留原格式和清楚的支持范围，产品开关挂起；后续在新窗口分别验证相册自身入口、另一受控系统版本/播放器。改变解码器不能直接修复外部系统相册。没有实现转换或大规模 fork；若后续需转换/原生桥，应先给出质量、CPU/内存、维护与隐私成本及明确授权，不自行扩范围。

## 设备恢复、环境与下一复验

最初旧 AV02 录制被中断，show_touches/pointer_location 未在 finally 内确认恢复；操作者手动关闭后已实际核对均0，原中断记录保留。其后所有录制均不改系统设置。此次最大字体与 TalkBack 由操作者开启/恢复；TalkBack 关闭后剩 vivo VisionAid 服务，用户明确要求“你给我关了”，仅关闭这一刚启用的确切服务并复核：字体1.0、方向锁0、触点0、指针0、accessibility_enabled0、启用服务列表为空。

10-13 使用已有共同 ADB，未重启。10-14 共同5037服务不存在后，在用户继续窗口内使用本任务新密钥/仅一台设备的独立5038服务；没有复制认证密钥/启动或重启共同服务。结束时已核对 PID/路径/one-device/端口，仅停止本任务服务器，归还手机；后续没有设备命令。

复验前需要新的明确空闲窗口；先只读核对共享资源、独立 SDK 可写与磁盘，再用现有验签 APK 核对单台设备/版本，执行清单的未验子项。已有 APK 与小型证据在 Git 外保留供复验；自有工具/签名/缓存的保留或清理以任务外收尾回执为准，禁止清理他人资源。

iOS 原生构建、Photos 导入/权限/相册/VoiceOver/真机仍 NOT_RUN：需要独立 Mac/Xcode/iOS 设备、受控保存入口与获准窗口；Android flavor 不能当 iOS scheme。准备入口后执行 `flutter build ios --debug --no-codesign --no-pub`，再逐项设备验收。MIV13 手机资源预算/支持上限仍 NOT_DEVELOPED_NOT_FIXED，MIV14 业务接入仍 NOT_DEVELOPED；不接主 App，不发布 Release、不部署、不合并 main。
