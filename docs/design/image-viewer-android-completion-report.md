# IV01 Android 本轮收尾记录

2026-10-14验收，2026-10-15 Git收尾，独立目录 `E:/Hnuhole-image-viewer-component-20261012/repo`，分支 `codex/image-viewer-component`。起始及测试时HEAD为 `d46ccac45f2a39abd8e4075dba6976be949e559c`，远端收尾前核对同SHA；测试针对本轮未提交源码。源码与此记录随本次Git提交交付，最终HEAD见包含本记录的提交及 `git rev-parse HEAD`，不把测试时HEAD冒称新代码提交。没有main合并、Release、部署或主App接入。

本轮交付固定输入资源边界、放大旋转修复和单台S18的Android证据。支持基线统一为Android10/API29，示例已实际minSdk29并移除旧写入权限；各当前设计链接[ADR0006](../adr/0006-android-platform-support.md)，其他任务运行时配置仍由其所属分支落实，认证环境与服务未改。历史旧系统证据保留，不视为新支持。

最后源码修改后实际通过：包108、示例5、两处分析、bundle、两个ARM64原生构建和验签。同一被测包摘要 `c6a88812da0e750d56f75c1392589ae4dd0ed3927f76ae77040d3a0e99a0b428`，137份文件的前后摘要稳定；收尾仅补文档，非文档源码逐文件核对一致。锁未删除/升级。完整命令与时间见[机器记录](image-viewer-android-completion-verification.json)，原日志根 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs`。

| 检查 | 实际Flutter参数（均带--suppress-analytics） | 结果 | 日志 |
|---|---|---|---|
| package-analyze | `analyze --no-pub` | PASS | `android-complete19-package-analyze.log` |
| package-tests | `test --no-pub` | PASS | `android-complete19-package-tests.log` |
| example-analyze | `analyze --no-pub` | PASS | `android-complete19-example-analyze.log` |
| example-tests | `test --no-pub test` | PASS | `android-complete19-example-tests.log` |
| bundle | `build bundle --debug --no-pub` | PASS | `android-complete19-bundle.log` |
| component-build | `build apk --debug --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-android-complete20261014 --build-number=20261019 --dart-define=VIEWER_ANDROID_DIAGNOSTICS=true` | PASS | `android-complete19-component-build.log` |
| nativecheck-build | `build apk --debug --no-pub --flavor=nativecheck --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-android-complete20261014 --build-number=20261019 --dart-define=VIEWER_ANDROID_DIAGNOSTICS=true --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true` | PASS | `android-complete19-nativecheck-build.log` |

执行入口为 `android-20261013/run-isolated.ps1`，Flutter3.47.5/Dart3.13.4、独立JDK17、Gradle9.3.1/AGP9.1与既有API35/36工具，SDK/cache/profile/temp均本任务E盘。没有升级共用SDK或下载大型工具到C盘。SDK XML版本警告非致命，两个原生构建exit0。

## 修复、API及输入/生命周期契约

18版手机放大后旋转丢失缩放，用户实际报告“缩放没有保留”；19版使用extended_image公开afterPaintImage保存已绘制阅读状态，布局恢复尚未生效时不清待恢复标记，防止重布局中间重置覆盖旧锚点。宿主补充放大、双向旋转及inactive/resumed竞争回归，19版用户复验“保留，好了”。真实状态日志保留3.5055倍及原归一化锚点恢复。没有fork、解码器或新原生桥。

新增公开 `ViewerResourceLimits`、`ViewerResourceUsage`、`ViewerController.resourceLimits/resourceUsage`、`ViewerFailure.resourceLimit`、保存 `maxOriginalBytes` 和 `ViewerSaveStatus.resourceLimit`。默认查看/保存16MiB；静态12×1024×1024像素、边16384；动画每帧1024×1024、总尺寸×帧数16×1024×1024、帧数120、单帧15秒/一轮60秒。通过Flutter提供的decoder检查后仍委托原codec逐帧解码，不缩图、不删帧、不改循环、不转GIF；帧时长逐帧检查，较晚超限可能已显示前帧，随后明确失败。

公共入口仍为ViewerItem/Source/Controller、HnuImageViewer及可选SaveCoordinator。组非空、索引有效、唯一稳定ID、声明有限正整数尺寸与实际帧一致；内容变更使用新ID。调用方提供已授权provider/来源及完整原文件，组件不接收账号、Bearer、密码或恢复材料，不建立长期私有磁盘缓存。绕过supplied decoder直接发布已解码图的自定义provider、来源读取/下载前分配预算由调用方负责，不能视为本组件拦截了外部分配。

只加载当前图；回顶同一次手势不退出，全部松手后新的下拉才能关闭。按ID恢复阅读和相对缩放；替换组开启新代次。关闭/失效/撤下为终态，迟到来源与保存结算不能污染新UI；onClosed只一次，调用方负责导航/dispose。隐藏时调用方同时设置TickerMode(false)。保存主动点击后才取原文件，进入adapter后不承诺取消；结算后才清自有临时文件，调用方文件不删除，未知结果不自动重写。详细入口见[包README](../../packages/image_viewer/README.md)。

## 实际设备/APK与资源

vivo S18/V2323A、Android15/API35、ARM64，两个独立示例实际安装versionCode20263019、minSdk29/target36。测试签名v2通过，证书 `77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5`；没有使用认证签名/秘密。

| 包 | 本轮APK SHA256 | 大小 | 保存 |
|---|---|---|---|
| component | `fa1d3a24f0c5a232f42f3932acef7af335b29d4ac74e3336fa4e21a0aa514f6a` | 91994977B | 默认关闭 |
| nativecheck | `5f7766b5f2661cf2ea429cb74ba8596965439c6523055d7f9e0759f61ab2e827` | 92011745B | 仅限定实验flavor＋define |

真实Android codec 45场景45PASS，含21份新方向/透明/长宽小图/大图/动画/超限素材与12次大图往返。EXIF1–8实际截图四象限方向/镜像全部相符。PSS基线338835KiB、峰值356219KiB（增量16.98MiB），末值340906KiB，末五次稳定；另12次开关最后PSS298561KiB。均为debug单台量测，不承诺release性能、进程绝对内存硬上限或其他硬件。16MiB编码上限有宿主拦截证据，手机素材编码最大1104462B（约1.05MiB），未对16MiB编码极限做手机压力证明。

## 逐项结果（范围与例外必须一起阅读）

| 项 | 结果 | 证据范围 |
|---|---|---|
| AV01 | PASS | 普通/长/宽/小/透明素材、EXIF1–8；Android实际45场景及8幅方向/镜像截图 |
| AV02 | PASS | 20263018人工多指正常；20263019修复版缩放旋转与双击恢复。完整抬指顺序保留18版本证据，不冒称19全量重跑 |
| AV03 | PASS | 20263019人工：同一次持续回顶不退出，全部松手后新下拉退出 |
| AV04 | PASS | 放大旋转缺陷在18复现，19修复并人工/真实状态复验；手指接触期间S18不触发旋转，该物理子项SKIP |
| AV05 | PASS | 20263019人工：下一张后返回保留原阅读位置，长图新会话进入顶部 |
| AV06 | PASS | 20263019六次关闭按钮、六次Android返回均回首页；人工合格下拉退出 |
| AV07 | PASS | 真实失败页、触摸重试恢复、访问失效退回；旧三秒来源在关闭后不能改变新页面 |
| AV08 | PASS | 真实迟到来源隔离及关闭终态；示例故障注入，不代证业务授权 |
| AV09 | PASS | 真实GIF/WebP解码计数：隐藏与后台停止持续解码，允许已在途的一帧；回前台继续 |
| AV10 | PASS | 系统字体1.88、TalkBack索引/按钮/禁用原因、失败/重试说明及保存成功/失败朗读、横屏布局。TalkBack双击重试未单独取得状态转移证据；普通触摸重试已验 |
| AS01 | PASS | API35自身MediaStore写入；新版minSdk29、无旧写入/全图库读取声明；此路径不弹拒绝授权，拒绝子项SKIP；API28以下用户移除支持 |
| AS02 | PASS | 真实Gal PNG/JPEG/透明PNG原字节一致；普通图保存成功大字反馈 |
| AS03 | PASS | 原GIF字节一致；Fossify1.14.0实际慢GIF1→2→3三组、末帧停住。约1秒截图采样不承诺毫秒级帧时长 |
| AS04 | PASS | 原有限/无限WebP字节一致；Fossify1.14.0自动两轮约2秒换帧并停末帧/无限持续变化。vivo9.4.6.13历史FAIL未改写/未修复 |
| AS05 | PASS | 两秒注入适配器中三次点击只一次派发/写入、一个新媒体项 |
| AS06 | PASS | 保存中关闭后原生写入继续，旧结果不污染新EXIF页；不能承诺系统取消 |
| AS07 | PASS | 两次故意删除本操作临时文件后调用真实Gal均失败、可再次操作、无新增媒体；库返回formatUnsupported不证明有效GIF不支持 |
| AS08 | PASS | 已采集的8次结算观察file/directory=false；最后两次WebP未再采集结算观察，不冒称它们单独通过清理 |

真实记录根 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/android-complete-20261014/logs`；机器记录保存各场景结果、原文件hash、解码/内存与实际相册截图采样。原屏幕只本地保留，未提交手机状态栏、设备serial或个人媒体；查询始终限定nativecheck owner及确切URI。

## 原格式保存与实际回放

8份本轮新媒体原字节全部一致，查看没有申请读取相册。API35的自身MediaStore写入无需旧写入授权，实际hasAccess=true；旧系统拒绝流程按用户移除支持SKIP，不以替身算平台权限PASS。

| 原素材 | 自有媒体ID | 字节 | 原始/系统文件相同SHA256 |
|---|---|---|---|
| ordinary.png | 1000043817 | 3656 | `6cc1d099a6d3ab59f6abbfcda73a023212e605623a768fe177d11f630cf2d964` |
| animation.gif | 1000043818 | 934 | `1343ba962a5e4754481cbd1227922a09445ad59819da0e17cadbec810392369c` |
| animation.gif | 1000043819 | 934 | `1343ba962a5e4754481cbd1227922a09445ad59819da0e17cadbec810392369c` |
| android_exif_1.jpg | 1000043820 | 1487 | `f4ab4302ffa13229a023af5df27663e4df4e4f361c8036fc3c5de7b25477f8f6` |
| android_transparent.png | 1000043821 | 349 | `db4c1b7f3f34c1b58ff2d92ed5feb9f7cdc3c4594709a5c58c17b8c0f72c709e` |
| android_gif_slow.gif | 1000043822 | 2892 | `96478521e9f3ccc23be7b3a90bcf0f788e8b86b394d391bfcdf30c991a734357` |
| replay_identity_slow.webp | 1000043823 | 10352 | `6da384a6f2a36b4ac27c29b6094e810796eb12e10aa68b236ff39d489c961e75` |
| replay_identity_fast.webp | 1000043824 | 10030 | `deb0286b961dfed5b0011dfdac6fd31a870dda78eeec84c71666a9bcc71ed988` |

Fossify Gallery1.14.0/versionCode29实际打开新保存文件：SLOW的无触屏截图序列1→2→3→1→2→3，观测换帧间隔1.903/2.054/2.048/1.931/2.145秒，末帧保持到14.907秒；慢GIF观测三组1→2→3并停末帧；无限WebP5秒内持续变帧。截图采样有约1秒分辨率，不能测80/120/200ms精确短帧时长，原文件时序/循环字节独立完整。外部PhotoActivity转到ViewPagerActivity，所有截图限定这两种查看页，未打开个人图库列表。

vivo Gallery9.4.6.13的首开/固定100ms调度/有限循环历史FAIL仍保留，未修改系统相册、未声称本轮修复或重跑该OEM版本。选定Fossify原文件回放PASS不代表所有系统相册通过。产品保存继续默认关闭，限定nativecheck可用，是否产品启用留到iOS/目标相册支持范围确定后。

## 剩余范围与复验

Android本轮结束，手机已交回；字体1.0、读屏关闭、原方向1、触点/指针0已实读恢复。使用用户明确允许的既有5037连接，未启动/重启/停止它、未创建/复制ADB密钥。相册读取权限在本轮打开前已为granted，未新申请/改变这些既有权限；只访问本任务合成URI。USB离线时停止输入/截图，仅用户恢复后继续；失败记录保留。

手指持续接触时S18不触发系统旋转，物理子项SKIP；宿主布局取消回归与普通放大旋转分开登记。TalkBack双击来源重试的独立状态转移未取证；普通触摸重试已恢复，按钮/说明/保存反馈读屏已验。最后两份WebP没有再单独取清理观察；已有8份实际结算观察与宿主协调层清理回归PASS，不能给未采集子项冒填证据。

iOS NOT_RUN：需隔离Mac/Xcode/匹配Flutter、受控iPhone窗口及独立示例签名；先原生构建，再Photos PNG/JPEG/GIF/WebP原文件完整性/实际回放、权限允许/拒绝/撤销、保存关闭竞争、旋转/多指/长图新手势、VoiceOver/大字、前后台及同一资源上限量测。gal iOS文件导入强制解包风险仍需最小合成文件核对；未经选择不转换GIF。Android其他硬件/release性能预算NOT_RUN，不能从S18debug量测推出普遍上限；有新授权窗口再按本清单补未取证子项。

MIV13 Android边界已实现并取得上述范围证据，iOS与release/其他硬件资源记录仍未完成；MIV14业务接入未开发，按用户要求继续独立，不接主App。M3双端正式验收和M4仍不完成。

运行时源码已保存提交 `67a14882621bd95520d7bac9e5407892593a4c5a`；交接文档在随后的同分支提交交付，最终HEAD以Git分支顶点为准。

自动审批拒绝了删除本任务APK副本的操作，仅返回“blocked by policy”。副本保留在独立目录，未纳入Git，没有重试或绕过拒绝。
