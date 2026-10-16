# IV01：相册身份、时序与有限循环复试

> **2026-10-14 相册兼容复验当前：**从已推送 `cdc31289` 接续，组件/示例/锁零改动。用户选择保留原文件，Fossify Gallery 1.14.0 在 vivo S18 上的 SLOW 自动播放、约2秒换帧、两轮结束 PASS，短有限/GIF/无限回放各有范围证据，4份播放后原文件 SHA 一致。vivo 9.4.6.13 无录屏仍失败；静态定位固定100ms调度/未处理有限循环，首开内部触发条件仍未确认。详见[兼容报告](image-viewer-gallery-compatibility-report.md)、[机器证据](image-viewer-gallery-compatibility-verification.json)及台账 currentImageViewerGalleryCompatibility。13:10结束设备操作，撤回新相册媒体权限、停止自有ADB/删除临时密钥。保存默认关闭；旧90＋5/构建证据保留版本，本轮未重跑；完整双端、预算和业务仍未完成。下方为历史记录。

2026-10-14（Asia/Shanghai）。**真实原文件写入完整；vivo Gallery9.4.6.13首次外部打开有限WebP不启动，切图后能显示目标文件的动画帧，但录屏中未遵循其帧时长/有限循环。**同一输入在这台手机的Android系统解码对照中约2秒换帧、两轮结束。问题已限定到该相册的播放初始化和动画时序/循环处理，具体内部函数/缓存或解析机制未确认。产品保存继续默认关闭；未转GIF、降质、fork解码器或加入生产原生桥。

[机器证据](image-viewer-gallery-identity-verification.json)包含实际命令、源码manifest、APK/素材SHA、已执行/失败/未验项。前轮[报告](image-viewer-webp-retry-report.md)和[记录](image-viewer-webp-retry-verification.json)保留版本，下列新增证据不改写为旧APK通过。

## 起点、改动与契约

独立目录 `E:/Hnuhole-image-viewer-component-20261012/repo`，仓库zewbby/HnuHole，origin `https://github.com/zewbby/HnuHole.git`，分支 `codex/image-viewer-component`。本轮实际起始HEAD **1852dda029ce12cb257487ab7e9748c24afee57c**，开始工作区干净。此前7ebce73f→3287607c→a20e5cfa→d7413522→1852dda保存历史保留。最终HEAD/远端、未提交状态和修改文件列表见Git与任务外 `webp-entry-retry-20261014/logs/entry-publication-receipt.json`；不写自引用提交哈希。

范围仅示例、合成素材/生成器/测试、nativecheckDebug诊断点位及IV01交接。`packages/image_viewer/lib`完全未改；公共API、稳定ID/尺寸/来源输入、终态/代次/迟到回调、保存lease/关闭竞争契约仍见[包README](../../packages/image_viewer/README.md)。默认四图组和所有既有素材字节不变；没有主App、认证、Go/SQL、上传/业务接口、依赖版本或锁修改，不接收真实账号/Bearer/密码/恢复材料。

新增 `create_replay_identity_controls.py`、SLOW/FAST两份192×144标记素材和一个实际Flutter解码测试；实验示例新增身份对照入口，仍需nativecheck+显式保存define。系统诊断只接受固定的slowIdentity/fastIdentity资产，用真实FIT_CENTER矩阵采样彩色带8×8像素，保留输入repeatCount；实际只跑slowIdentity，fastIdentity原生对照NOT_RUN。普通component的DEX中没有NativeWebpReplayProbe，nativecheck有该类/新fixture分支；未构建release。

## 实际设备与重试结果

仍为 **vivo S18/V2323A，Android15/API35、arm64-v8a**；实际相册9.4.6.13/9040613，dump里的9.3.24.0是回退包。用户新窗口“现在空闲，可以继续”，社区优先；从本任务新单设备5038服务开始，到**11:11停止操作并归还手机**。未改系统设置、未停止认证/共用服务。

| 项 | 本轮实际结果及范围 |
|---|---|
| 原慢有限直接进入 | 详情确认Pictures/original (1).webp，96×72/290B，原SHA f881…；红色首帧，启动FAIL。10秒录制文件实际可解码5.457秒，不声称录到完整10秒连续画面 |
| 操作者“会” | 后续截图实际是GIF标记、09:08的本任务GIF，未回原有限WebP；INVALID_TARGET，不计WebP通过。30秒录像没覆盖其实际切图，不能替代身份核对 |
| 原慢有限内部缩略图 | 文件名对上、出现快速颜色变化，但原/无限/GIF画面相同，不能仅凭文件名和变色证明正确源时序；INCONCLUSIVE。中途“能播”的初步判断已撤回 |
| 新任务外部打开 | NEW_TASK+MULTIPLE_TASK+读权限，flags0x18000001，实际LaunchState WARM；原有限仍首帧。未force-stop/清图库数据，不能把原因仅归为顶层旧Activity复用 |
| 新标记SLOW真实保存 | 原始10352B WebP逐字节完整、真实Gal成功且结算后自有文件/目录删除：PASS |
| 新标记FAST真实保存 | 原始10030B WebP逐字节完整、真实Gal成功且结算后清理：PASS；其完整平台时序/所有帧未验 |
| SLOW新任务外部进入 | 可见SLOW2s、FRAME1/3、LOOP2，红色首帧静止：启动FAIL |
| SLOW→FAST→SLOW | 两次单页ADB注入滑动，非人工手指；详情分别original (4).webp/FAST、original (3).webp/SLOW，192×144/正确大小。回到SLOW的确看到其FRAME2绿/FRAME3蓝：帧内容身份限定PASS；但时序/有限结束FAIL |
| SLOW系统解码对照 | 实际ImageDecoder/AnimatedImageDrawable输入SHA相同、repeatCount1，颜色红绿蓝红绿蓝、约2秒间隔，14秒running=false：限定PASS，不是相册通过 |

SLOW：每帧2000ms、rawLoop2，SHA **6da384a6f2a36b4ac27c29b6094e810796eb12e10aa68b236ff39d489c961e75**；FAST：80/120/200ms、rawLoop0，SHA **deb0286b961dfed5b0011dfdac6fd31a870dda78eeec84c71666a9bcc71ed988**。新标记素材全幅绘制不透明颜色和不同文字，比旧96×72透明色块更大；新素材通过不代证旧透明/完整格式矩阵。生成器逐帧RGBA断言、时长/循环断言、所有既有文件SHA不变；宿主codec实测3帧、循环、时长及两个不同像素内容。

真实保存项分别为确切自有URI1000043705/3706，owner为实验包、MIME=image/webp；读取完整性在保存后、相册播放前，不声称其他应用播放后永不修改文件。原生事件两次writeSucceeded和fileExists/directoryExists=false，API35 hasAccess=true，本次不跑旧存储权限拒绝分支。

## 时间与原因判断

返回录像总时长25.055989秒。稳定且无输入的媒体时间2–14秒中，SLOW标签与目标详情对应，却记录 **79次颜色变化**；绿色再次出现的周期中位约 **0.300秒**，相邻绿/蓝约0.1–0.2秒，至24秒以后仍变化。该稳定循环段只观察到绿/蓝，未见应再次出现的红色首帧，不能判“全部帧/原时序/有限结束PASS”。源文件应每帧2秒、共两轮，不是快速无限播放。[WebP循环/帧时长规范](https://developers.google.com/speed/webp/docs/riff_container)

离线先以实际SLOW/FAST截图的文字区域比对标记，并人工查看FRAME2绿/FRAME3蓝；随后用现成Edge关闭GPU/加速视频解码，**连续播放、requestVideoFrameCallback的实际mediaTime**独立核对，不做seek。320次呈现回调、实际播放25.063秒，再次确认快速持续颜色变化，避免只靠跳转取帧判断时间。两种分析仅解读真实手机录像，没用宿主生成动画替代真机。录像相册邻近缩略图条只存私有E盘，未查其原文件或入Git/上传。

系统原生对照对应源SHA：红7ms→绿1907→蓝3825→红5876→绿7935→蓝9853，ended9822，14秒running=false。回调在最后一帧开始时附近出现，不声称它精准计满12秒；可见两轮和有限结束与相册快速不停止明确不同。

**已证实是该相册的行为不符合保存文件时序/循环，未证实其内部代码原因。**切回SLOW时采用了近似FAST的速度且不结束，怀疑播放初始化/切图后动画状态或解析/调度未正确应用新文件；不把“继承旧FAST状态”写成已证明的内部机制，也不泛化所有vivo/Android/有限WebP。时序失败目前为**录屏条件下**，无录屏独立定时复核NOT_RUN。

当前Gal保存原始字节正确，Hnu核心未改；更换组件解码器不能控制外部com.vivo.gallery。没有扩大fork/自研播放器/生产桥；转换会涉及帧时序、透明、色彩量化、CPU/内存/维护与预算，未经另行选择不采用。保留原格式和明确支持边界，下一步受控其他相册/版本对照；不通过改loop0或转GIF掩盖失败。

## 最后修改后的宿主、原生构建与版本

继续使用已核对的任务私有E盘Flutter3.47.5/Dart3.13.4、Android SDK/JDK/Pub/Gradle/TEMP，runner每次核对102个包根与无链接工具根；不运行/升级认证SDK，不重装工具或向C下载大型缓存。开始磁盘C17.49GiB/E150.53GiB。锁SHA仍为包00ac99d693f003b46111d24e18a233741aedfd3501569130d57d731ca192fb81、示例9a7de0b094b07456d44016212168f2f5890e5a74d0bf4f708d77db6c51c95a24。

七项实际exit0、源码前后稳定，摘要 **080aa3dcb7c7b96cde5dce05b82aac0b2000fe2b646681128d8000196ffeffa7**。日志根 `E:/Hnuhole-image-viewer-component-20261012/android-20261013/logs`；每条同名JSON含命令/cwd/时间/HEAD/锁/manifest。最后一次修改后重跑，旧90＋4不代证90＋5。

| 目录 | 命令 | 本轮结果/日志名 |
|---|---|---|
| packages/image_viewer | flutter analyze --no-pub | PASS，identity-package-analyze |
| packages/image_viewer | flutter test --no-pub | 90 PASS，identity-package-tests |
| example | flutter analyze --no-pub | PASS，identity-example-analyze |
| example | flutter test --no-pub test | 5 PASS，identity-example-tests |
| example | flutter build bundle --debug --no-pub | PASS，identity-bundle，非原生证明 |
| example | 下方nativecheck命令 | PASS，identity-nativecheck-final |
| example | 下方component命令 | PASS，identity-component-final |

```text
flutter build apk --debug --no-pub --flavor=nativecheck --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-webp-identity20261014 --build-number=20261017 --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
flutter build apk --debug --no-pub --flavor=component --split-per-abi --target-platform=android-arm64 --build-name=0.0.0-webp-identity20261014 --build-number=20261017
```

两份ARM64-only、min24/target36、实际code20263017、v2验签PASS；仍是本任务独立测试证书SHA77cc0dd2bc5a71ffbf107ebfa6fdc74f3ca158bcb82548b53b6ae9dd9a421dd5。nativecheck **82195691B/adbe747b11c3b0d9e0e6c9dd9ebfd1f282451ad3a0f368d9bfcfa5b6cbdab49a**，实际原地更新Success及安装版本核对；component **82195423B/ac97751d88b2ca65560f4519dbd1a87a08120de0e6adfb8341725243a689ed71**仅构建/验签，本轮未安装，普通手机包仍20263014。前半未标记试验用20263016，保留各自版本。APK在任务外 `webp-entry-retry-20261014/artifacts`，不入Git。

## 收尾与待验

已返回手机首页，停止本任务PID33204/5038单设备服务，新私钥/公钥均删除；共用服务/认证环境/密钥未操作。最终只读字体1.0、自动旋转1、user_rotation0、触点/指针0、无障碍0、服务列表空；本轮不改设置。上轮遗留公钥的更正是上轮已完成的历史事件，本轮没有重复操作。现成隔离SDK、测试签名/APK及私有录像保留供未完成平台复验；复用了上轮视频复核profile/cache，旧删除BLOCKED已交接，不尝试其他工具绕过。

复验必须新明确设备窗口，先核对归属/版本/SDK写入隔离/磁盘。实验包选身份对照，保存并核对标签+详情+确切自有URI/输入SHA；外部进入与内部单页切回分开。下一轮不录屏，独立按秒观察SLOW帧号/颜色、两轮结束，并读播放后的文件SHA，再比较另一受控播放器/相册版本或相册自身列表入口。完整多指/放大旋转/后台/读屏大字、API24–28权限拒绝仍NOT_RUN；旧物理证据保留原APK，不重复封装。

iOS构建、Photos导入/权限/回放/VoiceOver仍NOT_RUN：需独立Mac/Xcode/设备与受控保存入口后执行 `flutter build ios --debug --no-codesign --no-pub` 和真实平台清单；Android flavor不是iOS scheme。MIV13资源预算/支持上限NOT_DEVELOPED_NOT_FIXED、MIV14业务接入NOT_DEVELOPED_NOT_INTEGRATED。不宣布完整Android/双端/M3/M4完成，不接主App、不合main、不发布Release、不部署。允许正常保存提交/推送本分支。
