# Android 默认保存与 S18 收尾

2026-10-15，Asia/Shanghai。Android 10/API29 起默认启用原格式保存，独立于 iOS 的待验状态。单台 S18 约定范围已收尾；不宣称所有 Android 硬件、所有相册或双端完整通过。TalkBack 按用户明确确认保留此前人工通过，不重复测试。

## 版本与范围

本轮实际起始 `8d57caf6e7bf596a4067389cfd2cbc0940d686f5`，目录 `E:/Hnuhole-image-viewer-component-20261012/repo`，分支 `codex/image-viewer-component`，origin `https://github.com/zewbby/HnuHole.git`。源码与 README 保存为 `76c35eba15fa8e098d6b18006f7693707d6bec5f`；最后 HEAD 为随后交接提交，见分支 Git 顶点。检查时是起始 HEAD 加本轮修改，运行时逐文件摘要与该源码提交相符；README 随后更新不改变被测运行时。

修改仅限包 `lib/src/viewer.dart`、`test/viewer_contract_test.dart`、示例 `lib/component_example.dart`、`test/component_example_test.dart`、`android/app/build.gradle.kts`、两份 README 与相关设计交接/台账。两个锁文件保留且字节未改；没有主 App、认证、Go、SQL、上传或业务接口修改。没有真实账号/密钥材料、设备 serial、手机截图、缓存、APK或大型制品入 Git。无强推、main 合并、Release 发布或部署。

## 公共 API 和契约

新增 `HnuImageViewer.enableAndroidSaving=true`：Android 非 Web、未注入协调器时创建并拥有真实 gal 协调器；iOS/桌面默认不创建。`enableAndroidSaving:false` 关闭自动入口；显式 `saveCoordinator` 优先，调用方拥有其 dispose。自动协调器在撤下、换 controller 或关闭自动入口时失效并 dispose，已经派发的原生写入继续结算/清理，迟到 UI 结果不会污染新页面。

必须同时满足当前图片 `saveAllowed`、完整原文件 `resolveOriginal`、成功加载、有效前台会话，按钮才可操作。只查看不请求相册权限或读取保存来源。PNG/JPEG/GIF/动态 WebP 按完整原文件写入，不转换、删帧、改时长/循环或降质。受保护来源由调用方授权；组件不接账号、Bearer、密码、恢复材料，不建立长期私有磁盘缓存。

稳定唯一 ID、有效组/索引和真实解码尺寸校验不变；同内容保留 ID，变更内容用新 ID。长图适宽从顶部进入；回顶同一次手势不能退出，全部松手后新下拉才允许关闭。阅读与相对缩放按 ID/布局锚点恢复；关闭/失效/撤下终结会话，旧加载和保存回调隔离。完整输入、生命周期与资源契约见[包 README](../../packages/image_viewer/README.md)。

## 实际检查和失败修复

隔离 Flutter3.47.5/Dart3.13.4、JDK17、Android SDK/NDK、Gradle/Pub/profile/temp 均在本任务 E 盘，未写认证共用 SDK、不升级全局工具或重装工具链。初始 C/E 可用19,165,835,264 /156,245,508,096B；结束19,099,541,504 /154,126,946,304B。复用用户允许的既有5037服务，未启动/停止/重启它，未创建/复制 ADB 密钥。原始失败日志保留，不以旧通过代证本轮。

最终实际命令与日志根 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs/`：

| 工作目录 | 命令 | 结果 | 日志前缀 |
|---|---|---|---|
| 包 | `flutter analyze --no-pub` | PASS | android-saving-final-package-analyze2 |
| 示例 | `flutter analyze --no-pub` | PASS | android-saving-final-example-analyze |
| 包 | `flutter test --no-pub --reporter=expanded` | 112 PASS | android-saving-final-package-tests |
| 示例 | 同上 | 7 PASS | android-saving-final-example-tests |
| 示例 | `flutter build bundle --debug --no-pub` | PASS，资源/kernel范围 | android-saving-final-bundle |
| 示例 | `flutter build apk --release --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-android-saving20261015 --build-number=20261021 --dart-define=VIEWER_ANDROID_DIAGNOSTICS=true` | PASS | android-saving-final-release |
| 示例 | 同构建参数，`--debug --build-number=20261022` | PASS，未安装 | android-saving-final-debug |
| 示例 | `apksigner verify --verbose --print-certs <本任务APK>` | 两份 v2 PASS | android-saving-final-release-signature / android-saving-final-debug-signature |

`run-build.ps1` 保存命令、隔离路径、源码前后 SHA 与锁摘要。检查串行执行；格式化后全部受影响检查重跑。

Release 最初失败：生成的 Java registrant 引用 dev-only `integration_test`，AGP release 正确排除了它；这版 Flutter 嵌套 assemble 又按默认 debug 模式生成注册文件。示例 Gradle 在 release javac 前只移除该测试插件的完整 try/catch 注册块，debug/instrumentation保留。首次替换表达式留下 catch 的编译失败已修正，经锁定离线 pub get 重新生成和最终 release/debug 构建验证；不移动 dev 依赖、不改 SDK、不新增桥。

示例新增测试最初失败：ready 在帧末通知，按钮断言早于下一帧；补一帧后恢复。16MiB 素材原先单个超大 ancillary PNG chunk 的宿主解码未结算，换成32个合法小块、独立核对 CRC 和边界字节；测试在真实异步区准备素材 IO，再验证实际 Flutter 解码/超限拒绝。修改时 IEND 索引错误已被测试捕获修正。最终7项通过，Release手机16MiB输入也实测成功；未修改用户图片或图片引擎。

## 实际设备和 APK

vivo S18/V2323A、Android15/API35、ARM64。独立 `org.hnuhole.image_viewer_component`，minSdk29/target36。实际安装 Release `20263021`，versionName `0.0.0-android-saving20261015`。本任务调试证书 SHA256 `77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5`，未复用认证秘密。诊断 define 只用于这些限定验收 APK，不是发布产品。

| APK | 字节 | SHA256 | 状态 |
|---|---|---|---|
| component20-debug | 91997981 | fd4f811106f3bf6906f8445ed778fbed97d37bb83674b5ad93bcc4a82bd6082e | 中间版本保存实测；后被Release替换 |
| component21-release | 19553979 | 0ebf674bedbb6fc1caa954df149ba2ca593ed97c67e5ffb7935ed0401bf4b544 | 最终运行时真机47项、默认保存PASS |
| component22-debug | 91998121 | a0cdf297fd2d14595dd4da1b2e6c5d59d32be3345b082264d9a6a59f97a3dbc8 | 同最终运行时构建/验签PASS，未安装 |

APK与手机日志在 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/android-save-default-20261015/` 的 artifacts/logs。手机更新首试返回 INSTALL_FAILED_ABORTED；用户允许后重试 Success，不算组件安装缺陷。截图只在自有示例前台采集，读取媒体只按本任务 owner/确切 URI。没有浏览个人图库。

## 本轮范围结果

| 目标 | 已实现 | 实际验证 / 状态 |
|---|---|---|
| Android 默认保存 | Android开启，iOS关闭；可显式禁用/注入 | 宿主平台/所有权4项、debug和Release真实PNG保存PASS |
| 输入、来源失败/重试、迟到隔离 | 既有实现保留 | 最终112＋7宿主PASS；物理交互保留20263019证据，未重复 |
| 阅读、旋转锚点、长图新手势 | 既有修复保留 | 20263019 S18人工及状态证据PASS，完整抬指顺序保留18版本；同手势回顶/新下拉PASS |
| 按钮、TalkBack、大字 | 既有实现保留 | 用户明确“TalkBack所有的都已经通过”，保留19版本人工PASS；此前报告遗漏的是独立截图状态转移，不再视为功能未验；本轮未重复 |
| 原生权限、失败和竞争 | 既有真实 gal 适配 | API35自身MediaStore无需读取/旧写入授权；拒绝子项SKIP非适用，API28以下SKIP已移除支持；连点/关闭竞争/临时消失保留19版本实际PASS |
| WebP原字节与临时清理 | 原文件写入、结算清理 | 本轮有限/无限两份真实写入与SHA一致，file/directory=false PASS，补齐此前未单独观察项 |
| Release资源与16MiB编码边界 | 默认资源拒绝政策不变 | S18 Release47/47PASS；16MiB实际ready151ms，+1字节resourceLimit87ms；12次大图往返符合预期 |
| GIF/WebP相册回放 | 保留原文件 | Fossify1.14.0此前保存原文件实际回放PASS，旧范围证据保留，不重复；vivo兼容问题下节单列 |
| iOS | adapter已有，默认不自动启用 | 原生构建、Photos、权限、VoiceOver、触摸/资源NOT_RUN |
| 业务接入 | 未开发 | MIV14按用户范围不接主App；非“只差测试” |

Release 16次PSS采样132948–183251KiB，末值162835KiB（非GC后基线或精确峰值），记录的最大build15953µs/raster16032µs。是真实优化模式单台样本；不能推广所有硬件/性能SLA，采样间峰值未知，不承诺绝对内存硬上限。已补本台Release记录和编码16MiB边界；跨Android版本/其他硬件仍NOT_RUN，不是要求用户找旧系统。

本轮保存文件：PNG 1000043825、有限WebP 1000043826、无限WebP 1000043827、Release PNG 1000043828，均为本任务component owner；分别3656/10352/10030/3656B，与仓库合成来源SHA一致。三次debug及一次Release结算观察均fileExists=false、directoryExists=false。来源hash与脱敏事件见[机器证据](image-viewer-android-saving-verification.json)。

## vivo 相册单独兼容记录

当前手机相册仍9.4.6.13（9040613，target35/min30），当前OS是Android15，在支持范围内。没有证据证明是“仅过老版本”或新版已经修复，不能据此删除事实。历史有限WebP首开静止、内部切回后固定100ms/忽略有限结束FAIL，具体首次启动内部条件尚未确认；未改系统相册、不把它算组件保存失败、不再阻止Android默认保存。Fossify1.14.0对相同原文件自动约2秒/两轮停止PASS；库成功写入、文件完整性、播放器兼容三者分开登记。未来相册更新只需重验该播放器，不必关闭组件保存或再次重跑TalkBack。

## 交还和后续

10:29（Asia/Shanghai）结束设备操作，手机可交回社区。字体1.0、自动旋转0（本轮初始即0）、触点/指针0、辅助服务空已只读核对；本轮没有写系统设置或更改媒体权限。既有ADB服务保留，后续设备操作需新窗口。

iOS继续独立NOT_RUN：隔离Mac/Xcode/匹配Flutter及受控iPhone、独立签名；先锁定依赖和示例原生构建，再Photos完整PNG/JPEG/GIF/WebP回放/权限允许拒绝撤销/保存关闭竞争/清理、多指/旋转/长图新手势、VoiceOver/大字、前后台与同资源边界。风险包括gal iOS导入强制解包，须合成最小复现，不能宿主替身代证。原文件不满足时先报告兼容选择，不自行fork/转换/原生桥。Android其他硬件/版本和长期资源预算按独立任务补；M3双端正式验收及M4业务仍未完成。完成本轮普通提交/推送后以远端HEAD为准。

APK和隔离缓存留在本任务E盘，未提交。此前自动审批拒绝删除APK，仅返回“blocked by policy”；没有重试或绕过删除，不影响本轮功能/测试和Git交付。
