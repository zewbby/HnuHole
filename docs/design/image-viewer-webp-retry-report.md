# IV01：有限循环 WebP 相册复试与原因定位

> **2026-10-14 相册身份/时序复试当前：**从已推送1852dda接续，只增带SLOW/FAST、帧号和循环标记的合成对照、示例测试与系统解码诊断点位；核心组件/API/锁/旧素材不变。最后修改后包90＋示例5、两处分析/bundle及两份ARM64 Android构建/验签PASS，实验手机包20263017、普通手机包仍20263014。真实Gal两份原文件SHA/结算清理PASS；vivo Gallery9.4.6.13外部有限首帧启动FAIL，内部切回确认为SLOW自身Frame2/3，但录屏中约0.1–0.2秒换色、超过有限时长仍循环，时序/结束FAIL。相同输入Android系统对照约2秒两轮并结束PASS。旧“会”截图实际GIF，不算WebP通过；文件名/变色不足以判完整回放。具体相册内部缺陷未确认，产品保存仍默认关闭，无转换/降质/fork/生产桥。见[身份报告](image-viewer-gallery-identity-report.md)、[机器证据](image-viewer-gallery-identity-verification.json)及台账currentImageViewerGalleryIdentity。11:11已归还手机/停止私有单设备ADB/删除新密钥，未改系统设置；完整平台矩阵/iOS未验，预算和业务未开发。旧证据保留版本，下方不代证当前。

2026-10-14，Asia/Shanghai。**问题已限定到这台 vivo S18 的 vivo Gallery 9.4.6.13 有限循环 WebP 启动/恢复路径；相册内部具体缺陷尚未确认。**相同原始字节经真实 Gal 保存完整，在 Android 系统解码对照中能播放并结束；相册直接打开慢速有限文件仍停在首帧，无限文件则能自动播放。没有通过改写循环次数、转换 GIF、降质或替换引擎掩盖失败，产品保存仍默认关闭。

机器记录：[复试 verification](image-viewer-webp-retry-verification.json)。原完整单台交互/保存结果保留在[上一报告](image-viewer-android-device-report.md)及[原记录](image-viewer-android-device-verification.json)，不冒称本轮重新跑了全部手势或权限。完整 Android、iOS、M3/M4 均未通过。

## 版本与改动

- 仓库 `zewbby/HnuHole`，origin `https://github.com/zewbby/HnuHole.git`，分支 `codex/image-viewer-component`，独立目录 `E:/Hnuhole-image-viewer-component-20261012/repo`。
- 本次起始、检查和构建时 HEAD：`d74135227a06ef3e677850b210bf8b2445722a28`，此前已正常推送。整体阶段起始仍为 `7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`，之前保存提交 `3287607c`、`a20e5cfa`、`d7413522` 保留。
- 当前提交保存本轮源码、测试及脱敏记录。最终 HEAD/远端与提交前文件列表见 Git 及任务外 `webp-retry-20261014/logs/retry-publication-receipt.json`；不写循环自引用的提交 SHA。没有强推、合并 main、发布 Release 或部署。
- 只新增示例回放对照、一个合成素材、其生成器/测试和 `nativecheckDebug` 系统解码诊断 Activity。`packages/image_viewer/lib` 完全未改，公共 API、输入/生命周期/保存 lease 契约不变；锁和所有既有素材原始字节不变。不接主 App、不改认证/服务端/上传/业务接口，不使用账号、Bearer 或其他认证材料。
- 新素材生成器只添加 `animation_replay_slow.webp`，断言既有素材未被重写、解码 RGBA 与原三个帧一致、每帧 2000ms、rawLoop2。没有对实际待保存图片实施转换。

## 实际对照及结论

设备仍为 **vivo S18/V2323A，Android15/API35，arm64-v8a**；系统相册 `com.vivo.gallery` **9.4.6.13 / 9040613**。本次另获“手机空闲，可以复试”窗口，社区优先。只打开本任务已核对 owner 的合成媒体；不浏览或读取其他照片原文件。

| 素材 | 真实文件/循环 | 实际结果 |
|---|---|---|
| 原短有限 `animation.webp` | 96×72，290B；80/120/200ms，rawLoop2，总0.8秒 | 上轮直接打开首帧静止 FAIL，保留当时20263014版本；本轮不冒称再跑此文件 |
| 新慢有限 `animation_replay_slow.webp` | 96×72，290B；每帧2秒，rawLoop2，总12秒 | Gal 保存字节一致 PASS；相册外部直接进入仍红色首帧 FAIL，人工“没有，现在一直是红色的”；在相册前台从本任务PNG切入也红色静止 FAIL |
| 既有无限 `animation_infinite.webp` | 96×72，290B；80/120/200ms，rawLoop0 | Gal 保存字节一致 PASS；从本示例外部进入相册，不触屏持续变色 PASS，人工“OK了”及实际录像帧支持；相册已前台的一次切URI仍显示旧PNG，目标未打开，该次 NOT_RUN |
| 同一慢有限文件的 Android 系统解码对照 | 打包字节 SHA 与相册保存文件完全相同；系统解析 repeatCount1（首轮之后再重复一次），未覆盖循环次数 | 实际手机 stock ImageDecoder/AnimatedImageDrawable 播放两轮并结束，限定 PASS；不是相册通过 |
| 同一无限文件的 Android 系统解码对照 | 相同保存字节 SHA；系统 repeatCount=-1 | 实际手机14秒观察期间持续变化、结束观察前仍 running=true，限定 PASS；随后人为 stop，不称自然结束 |

慢有限原始/保存 SHA256：`f881330695568fd135112d6ce63c547f7fe0773d9c7e18f4b28294fd6ad99be6`。无限原始/保存 SHA256：`e8d714336d16477d76cf01515d61a8e9916babd87ee093434bbd1638ead40e76`。两次真实原生写入均成功，结算后自有文件和目录不存在，权限检查 granted=true；本 API35 分支不申请旧存储权限。权限拒绝未在本轮重跑。

原短有限和既有无限文件的 **290字节只有偏移42的一字节不同：ANIM循环数2→0**。这不是尺寸、帧数据、压缩或质量差异。规范规定非零循环数为总播放轮数、0为无限；正常完成应保留最终帧，不能把一直停在首个红色帧当作正常播完。[WebP 容器规范](https://developers.google.com/speed/webp/docs/riff_container)

上述结果排除了“保存损坏或转换导致动图丢失”，也排除了仅以0.8秒太短、没赶上观察解释本次慢有限失败。Android 实际系统对照说明该有限文件可被平台识别为动画并播放；无限文件在该相册能播，不能泛化为此手机或相册完全不支持动态 WebP。

**剩余原因判断是有证据的定位，不是已证实的内部函数结论。**当前最小复现指向该相册对有限循环的启动/恢复处理；尚无相册源码、其实际解码器调用或其他设备/相册版本的证据。不能断言它使用某个解码器、哪行代码错误，或所有有限 WebP 必然失败。Android 官方接口要求调用 start 才运行；对照确实保持文件自身 repeatCount 并显式 start。[AnimatedImageDrawable](https://developer.android.com/reference/android/graphics/drawable/AnimatedImageDrawable)

操作者后续答复“必须左右切图才开始动，不然不动”。尚未收到动图详情文件名，不能排除切到了邻近 GIF/无限 WebP；同一个有限文件返回后的回放 **NOT_RUN**。上轮“拖动后PASS”仅保留看到动画的操作者报告，本次已给原报告/记录加限定，不能当作原有限文件自身通过。

## 验证方法及失败尝试

相册录制均先核对确切 MediaStore URI 的 owner，使用 ACTION_VIEW 打开该 URI；录制时不自动点按、不改系统设置。外部进入先回到本任务示例；前台切换先打开本任务已知PNG。录像的白色相册背景、主图区域色块变化和操作者答复共同判断，黑色 Flutter 查看器帧不能混入相册播放证据。

- 无限外部进入录像：相册主图可见约2.3–9.6秒，连续绿/蓝变化；0.1秒离线取帧可能漏掉80ms红帧，不冒称自动检测到完整红绿蓝序列。
- 慢有限外部进入录像：主图可见约2.3–9.5秒，仅红色。慢有限前台切换：约1.8–9.6秒仅红色。均超过单帧2秒时长，不能视作正常自动回放。
- 无限前台切URI：ADB提示 Intent 交给当前顶层实例，实际仍为旧PNG。该次目标图片身份不成立，不计入动画通过或失败。
- 系统对照第一次切 infinite 同样复用了已有 slow Activity，未出现对应 decoded 事件；该次 NOT_RUN。关闭旧页、重新创建 Activity 后出现确切 infinite SHA/repeatCount/帧事件，才计通过。复验必须先关闭上一次对照。

`NativeWebpReplayProbe` 仅在 `nativecheckDebug` 源集，实际APK manifest 已核对：普通 component 不含该 Activity、实验 debug 包含；release 源集不包含该类，但本轮没有构建/验证 release。它不读系统相册、不导出、不接收任意路径/URI/账号，不建立 Flutter 平台桥；fixture只允许short/slow/infinite，使用现成 Android 能力，不自研解码器。

对照用 PixelCopy 观察**本合成图片中心8×8像素**，记录分类及开始/结束回调，不保存全屏截图。慢有限 trace 为 `other→green→blue→other→green→blue`，其中 other 是中心落在背景或未分类颜色，不能称自动识别到红帧；这些可见变化与 repeatCount/start/end共同证明动画实际运行。有限 ended 在约9854ms记录，最终蓝色约9911ms观测到，14秒时 running=false；不把回调时间声称为精确12秒动画计时验证。无限14秒时仍运行，之后 stop 触发的 ended 是测试结束，不是自然有限回放。离开页面移除定时任务、停播并清除窗口临时 keep-screen-on。

原始录像、截图、MediaStore查询与限定本任务PID的日志留在私有 E 盘。相册邻近缩略图条没有入 Git或上传，也未读取其原文件；仅脱敏机器记录/摘要入库。

## 最后源码修改后的检查与 APK

日志根：`E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs`。仍用既有私有 E 盘 Flutter3.47.5/Dart3.13.4、Android SDK/JDK/Gradle/Pub/TEMP，未升级共用SDK、安装新依赖或向C下载大型缓存。最近盘点 C可用17.63GiB、E150.75GiB。SDK XML版本警告保留于日志，两个构建 exit0。

以下七项源文件前后稳定，完整包摘要均为 **`d6f1f0ff9facb2a9fd6daf56ef86dc941144ecc68a18675c34676eb332b26deb`**。每条 `.json` 保存实际命令、时间、HEAD、manifest及锁摘要；机器记录只保留一次完整 manifest。旧90＋3不能代证本次90＋4。

| 目录 | 实际命令 | 结果 | 日志名（.log/.json） |
|---|---|---|---|
| packages/image_viewer | flutter analyze --no-pub | PASS，无问题 | webp-framework-package-analyze |
| packages/image_viewer | flutter test --no-pub | PASS，90项 | webp-framework-package-tests |
| example | flutter analyze --no-pub | PASS，无问题 | webp-framework-example-analyze |
| example | flutter test --no-pub test | PASS，4项 | webp-framework-example-tests |
| example | flutter build bundle --debug --no-pub | PASS，Dart/kernel/资源编译 | webp-framework-bundle |
| example | 下方 nativecheck命令 | Android原生构建PASS | webp-framework-nativecheck-final |
| example | 下方 component命令 | Android原生构建PASS | webp-framework-component-final |

```text
flutter build apk --debug --no-pub --flavor=nativecheck --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-webp-framework20261014 --build-number=20261016 --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
flutter build apk --debug --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-webp-framework20261014 --build-number=20261016
```

锁 SHA 不变：包 `00ac99d693f003b46111d24e18a233741aedfd3501569130d57d731ca192fb81`；示例 `9a7de0b094b07456d44016212168f2f5890e5a74d0bf4f708d77db6c51c95a24`。

| APK | 实际版本/字节/SHA256 | 设备状态 |
|---|---|---|
| nativecheck，0.0.0-webp-framework20261014-nativecheck | code20263016，82182297B；079f659ad61f4a809ba5628850563c3c78ac12d67add1ca88a3fc2425fabfd76 | 实际安装核对，系统解码对照用此版 |
| component，0.0.0-webp-framework20261014 | code20263016，82173473B；593cfc1f9852ae5f69e5a8cadd336814afdf40f76ccb107e44b5ca73fe4b68c0 | 构建/验签/manifest通过，本轮未安装，手机普通包仍20263014 |
| 先前本轮 nativecheck，0.0.0-webp-retry20261014-nativecheck | code20263015；6671bf24134facee0d590cd32f5f89e69be0b5c54fe5b041f5756ddcef4db1b3 | 两次Gal写入和相册录制用此版，之后由20263016原地更新 |

APK保留任务外 `android-20261013/webp-retry-20261014/artifacts`，ARM64-only、min24/target36。最后两份 v2验签PASS，仍用本任务独立调试证书SHA `77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5`，不复用认证签名。两次本轮原地更新均 Success，无卸载回退。

## 收尾、更正与后续门槛

本次窗口10:01开始，10:25结束；未修改系统设置。最后只读结果：font_scale1.0、自动旋转1、user_rotation0、触点0、指针0、accessibility_enabled0、服务列表空。自动旋转1仅记录当时实际值；本轮未改方向设置，不能写成恢复到上轮0。

本任务单设备5038 ADB服务已核对PID/可执行路径/one-device后仅停止自己；本轮私钥与公钥都实际删除。共用 ADB/认证服务未启动、重启或停止，手机交回社区。**更正上一阶段清理声明：**旧实际回执为私钥已删、公钥未删，旧机器记录却写两者已删；本轮开始只删除已确认归属的遗留公钥，并在旧记录加更正，保留原始回执与旧测试结果。没有触碰共用密钥。

现成隔离工具链、任务测试签名/APK和私有原始证据暂保留于Git外，供尚未关闭的平台复验；不清理他人资源。再次设备操作必须新明确空闲窗口，先核对社区优先与工具/设备归属，不隐式启动或重启共用服务。

本轮离线视频复核浏览器 profile/cache 的递归删除被自动审批策略拒绝（`blocked by policy`，未提供更细原因）；只读核对目标均在本任务重试目录、profile无链接后，采用静态绝对路径的安全重试仍被拒绝。缓存清理登记 BLOCKED，未改用其他工具绕过；这些缓存仍在本任务E盘、未入Git。该限制不影响已完成的ADB停止和临时私钥/公钥删除。

复验步骤：

1. 先核对本分支/锁/源码、私有SDK写入隔离及剩余磁盘。重建上述限定APK，记录实际SHA/签名/版本；安装前确认唯一空闲设备和本任务包归属。
2. 实验包首页打开“相册回放对照”，分别保存慢有限和无限原文件。核对真实Gal阶段、owner、取回SHA与临时清理；用确切自有URI打开相册并从进入时开始无触屏观察≥6秒。
3. 从相册自己的受控入口打开同一个有限文件；切出/切回后用详情核对文件名/扩展名/已知文件身份，再观察。只有身份核对后才能计“左右返回后同文件回放PASS”。不要横向翻到未知私人照片或清除相册数据。
4. 对系统解码对照，每次先关闭上一对照页，再执行示例README中的显式Activity命令。核对decoded中的fixture/SHA/repeatCount、实际visibleColor和start/end；出现“intent delivered to currently running top-most instance”且没有新fixture decoded时该次无效，先关闭后重试，不计为解码失败。
5. 比较另一已获准设备/相册版本或已有受控播放器；不盲目更新系统相册、不安装大型工具、不修改导出的循环次数。内部缺陷未确认前保留本最小复现；组件替换解码器不能直接修复外部相册，任何大规模fork/转换/原生桥须先报告必要性、质量/CPU/内存/维护成本及替代方案。

其他门槛保持单列：API24–28权限拒绝/重授予、完整旋转/多指/后台/读屏/大字矩阵未验；iOS原生构建/Photos导入、真实权限、VoiceOver与设备回放NOT_RUN，需要独立Mac/Xcode、受控保存入口与获准设备窗口后执行 `flutter build ios --debug --no-codesign --no-pub` 并逐项实测。MIV13资源预算/支持上限NOT_DEVELOPED_NOT_FIXED，MIV14业务接入NOT_DEVELOPED_NOT_INTEGRATED。公共API/生命周期契约见包README；不接主App，不把宿主或系统解码对照写成完整相册或双端通过。
