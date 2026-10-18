# 独立图片组件示例

> **2026-10-15 当前入口：**Android 10/API29 起的 `component` 和 `nativecheck` 均默认启用原文件保存，不等待 iOS。iOS 默认关闭；其显式实验开关保留。普通示例不包含故障注入入口；`VIEWER_ANDROID_DIAGNOSTICS=true` 仅在限定测试 APK 中显示资源、回放对照和真实 Gal 故障注入。当前 S18 安装 ARM64 Release 20263021，最终 debug 构建20263022未安装；包112＋示例7/分析/bundle/两种构建与验签通过，Release真实47项全通过。见[本轮报告](../../../docs/design/image-viewer-android-saving-report.md)。下方有日期的条目按原版本理解。

构建使用匹配的隔离 Flutter/Android SDK/JDK 与缓存，保留锁。`flutter build apk --release --no-pub --flavor=component --split-per-abi --target-platform=android-arm64` 可构建正式优化模式的独立示例；这里只用本任务测试签名，不是商店发布。Flutter3.47的嵌套 assemble 会把调试测试插件重新写入 Java registrant，示例 Gradle 在 release javac 前只移除 integration_test 的生成注册块；debug/instrumentation保留。无需修改或升级共用SDK。

> **本轮Android证据：**包108＋示例5、分析/bundle/两份原生构建通过；S18/API35实际20263019，修复缩放旋转并固定资源边界。原格式保存及选定Fossify回放通过；默认保存关闭、iOS与未取证子项单列，见[收尾报告](../../../docs/design/image-viewer-android-completion-report.md)。下方旧日期记录保留原证明范围。

> **2026-10-14 Android 收尾入口：**最低 Android 10 / API29，旧 WRITE_EXTERNAL_STORAGE 配置与旧系统验收移除。仅本任务包可用 `--dart-define=VIEWER_ANDROID_DIAGNOSTICS=true` 显示合成素材自动核对入口，并输出脱敏尺寸/帧计数和Android解码结果；它不调用图库、不包含账号或认证接口。默认查看包仍关闭保存，限定 nativecheck 保存开关不变。Android 设计基线见 [ADR 0006](../../../docs/adr/0006-android-platform-support.md)。下方旧日期命令/系统范围为历史记录。

新增“Android 格式与资源验收”包括八种JPEG EXIF方向、半透明、小图、宽图、边界大图/长图/动画/高帧数和明确超限失败。“自动核对 Android 素材与资源”只使用本地合成图片、实际Flutter平台解码，不注入手势或代证人工多指/读屏；每项结果与12次大图往返写入日志。“临时隐藏四秒”使用Offstage+TickerMode，实际生命周期/后台由设备单独验证。源码生成器保留已有fixture SHA，未转换用户原文件。

默认 `main()` 启动 `ComponentApp`，使用当前公共 API 和本地合成图片，展示惰性来源、失败重试、访问失效及调用方导航。`runM1Probe()` 保留原技术样例；它与原 M1 设备测试不能代证当前组件验收。

先读 [包 README](../README.md) 与 [机器交接](../../../docs/design/image-viewer-machine-handoff.md)。保留锁文件并使用可独立写入的 SDK/Pub/TEMP，不能复用正在认证验收的环境、服务或设备。

宿主：`flutter analyze --no-pub`、`flutter test --no-pub --machine --concurrency=1 test/component_example_test.dart`、`flutter build bundle --debug --no-pub`。bundle 只证明 Dart/kernel 与资源编译。

2026-10-13 Android 准备改用两个独立包名：普通 `org.hnuhole.image_viewer_component` 与限定保存实验 `org.hnuhole.image_viewer_component.nativecheck`。iOS bundleId 仍为 `org.hnuhole.imageViewerM1`，Mac 构建及其受控保存测试入口继续单列。Android 的实际结果、APK 指纹/签名与设备窗口状态见 [Android 交接](../../../docs/design/image-viewer-android-report.md) 和 [单台清单](../../../docs/design/image-viewer-android-checklist.md)。无窗口前不得执行设备命令。

```text
flutter build apk --debug --no-pub --flavor component --split-per-abi --target-platform android-arm64 --build-name 0.0.0-platform20261013 --build-number 20261013
flutter build apk --debug --no-pub --flavor nativecheck --split-per-abi --target-platform android-arm64 --build-name 0.0.0-platform20261013 --build-number 20261013 --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
flutter build ios --debug --no-codesign --no-pub
flutter test integration_test/image_viewer_component_device_test.dart --flavor component -d <已获准设备ID>
```

iOS 命令仅在 Mac/Xcode；Android flavor 不设为跨平台默认，以免引入未配置的 Xcode scheme。保存实验默认关闭；Android 只有 `nativecheck` flavor 和 `VIEWER_ENABLE_NATIVE_EXPORT=true` 同时满足才启用，普通 flavor 单独传 define 也保持关闭。设备导出入口须另外明确窗口、操作者和相册核对；使用 `--flavor nativecheck -d <已获准设备ID> --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true`。API29+ 的直接导入不申请此存储权限，权限拒绝适用性按设备记录。插件结算、文件完整性、相册播放分开验收，未默认转换 GIF 或降低质量。

示例新增“延迟加载与关闭隔离”，合成来源等三秒再返回；关闭后立即打开另一图，核对旧来源不污染新页面。nativecheck 保存实验还提供两秒适配器延迟和自有临时文件删除故障注入，实际保存调用仍走 gal。`VIEWER_PLATFORM_EVENT` 输出阶段与操作序号及清理布尔值，不输出私有路径或原异常；注入延迟不称原生性能，故障注入不称系统自行发生的故障。真实系统行为全部以设备执行为准。

旧技术测试单独使用 `integration_test/image_viewer_device_test.dart`；其保存开关仍为 `M1_EXPORT_FIXTURES=true`，只属于 M1 历史技术场景。两条入口分别记录源码版本及证明范围，不混用。

2026-10-14 WebP 复试增加“相册回放对照”入口，仅 nativecheck+显式保存开关可见：原短有限 WebP（总0.8秒）、慢有限 WebP（每帧2秒、两轮12秒）、无限 WebP和GIF。生成器 `../tool/create_replay_control.py` 只添加慢有限素材并核对既有素材字节不变；不会改写用户文件或默认转换。入口与真实相册回放分别验收。

`nativecheckDebug` 还包含仅合成素材的 `NativeWebpReplayProbe`，其他 flavor 和 release 均没有此 Activity。API28+ 用系统 ImageDecoder/AnimatedImageDrawable，不覆盖 repeatCount，显式 start；仅观察本测试图片中心8×8像素颜色及开始/结束回调，不读系统相册、保存截图或建立 Flutter 原生桥。获准设备窗口内可执行：

```text
adb -s <已获准设备ID> shell am start -n org.hnuhole.image_viewer_component.nativecheck/org.hnuhole.image_viewer_component.NativeWebpReplayProbe --es fixture slow
```

fixture 仅接受 short/slow/infinite，不接受路径、URL、账号或授权材料。每次观察14秒，离开页面停止并移除定时回调；keep-screen-on 只在此页面临时有效，不修改系统设置。API24–27直接记录未运行。结果见[WebP复试报告](../../../docs/design/image-viewer-webp-retry-report.md)，系统解码对照通过不能代证系统相册通过。

相册身份与时序对照仅在保存实验入口：SLOW 2s（每帧2秒、两轮）和FAST（80/120/200ms、无限）使用192×144的不同可见文字、帧号与循环标签。`create_replay_identity_controls.py`只生成这两份合成素材，核对既有文件不变。相册详情文件名改变不足以证明显示内容已切换；须同时核对画面标签、实际换色间隔及有限结束，不能把残留的旧动画或错误时序算通过。

系统解码诊断另接受 `slowIdentity` / `fastIdentity`，仍只对应这两份打包合成文件；用真实FIT_CENTER矩阵定位标记图下方的彩色带，不把上方静止文字当作动画帧。
