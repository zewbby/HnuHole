# IV01 单台 Android 平台验收清单

> **2026-10-15 当前 Android 收尾：**Android10/API29 起默认启用原文件保存，iOS 独立保持关闭。源码提交 `76c35eb`；最终包112＋示例7、两处分析/bundle、ARM64 debug/release构建/验签PASS；S18/API35实际Release20263021真实47项全通过，补齐16MiB编码边界及两份WebP原字节/结算清理。TalkBack按用户确认保留既有人工PASS，不重复。vivo9.4.6.13问题单列播放器兼容，不阻止保存；无仅因过老版本的证据。手机已交回，设置未改、既有ADB未动；见[本轮报告](image-viewer-android-saving-report.md)和[机器证据](image-viewer-android-saving-verification.json)。iOS、其他硬件/版本、业务接入仍各自单列；下方旧日期状态保留历史，不代证当前。

> **2026-10-14 Android本轮收尾：**从d46ccac接续，统一Android10/API29设计并实际提高独立示例minSdk；新增资源边界，修复手机放大旋转丢缩放。最后修改后包108＋示例5、分析/bundle与两份ARM64原生构建/验签PASS，实际S18/API35/APK20263019。45真实codec场景、8幅EXIF、前后台/隐藏、12开关、长图新手势/阅读恢复、TalkBack/大字和原格式保存/竞争取得范围证据；Fossify1.14.0新保存文件回放自动复核PASS。vivo9.4.6.13历史FAIL保留，保存默认关闭；iOS/release与其他硬件/业务仍单列，未取证子项见[本轮报告](image-viewer-android-completion-report.md)和[机器记录](image-viewer-android-completion-verification.json)。手机已交回，设置恢复，既有ADB服务未改；本轮直接普通提交/推送，不发布/部署/main合并。下方保留原版本历史。

> **Android 统一支持范围（2026-10-14）：**本设计遵循 [ADR 0006](../adr/0006-android-platform-support.md)，最低 Android 10 / API29；Android 9 / API28 及以下不适配、不列为新验收门槛。历史测试保留原版本；所属任务另行核对运行时配置。

> **2026-10-14 相册兼容复验当前：**从已推送 `cdc31289` 接续，组件/示例/锁零改动。用户选择保留原文件，Fossify Gallery 1.14.0 在 vivo S18 上的 SLOW 自动播放、约2秒换帧、两轮结束 PASS，短有限/GIF/无限回放各有范围证据，4份播放后原文件 SHA 一致。vivo 9.4.6.13 无录屏仍失败；静态定位固定100ms调度/未处理有限循环，首开内部触发条件仍未确认。详见[兼容报告](image-viewer-gallery-compatibility-report.md)、[机器证据](image-viewer-gallery-compatibility-verification.json)及台账 currentImageViewerGalleryCompatibility。13:10结束设备操作，撤回新相册媒体权限、停止自有ADB/删除临时密钥。保存默认关闭；旧90＋5/构建证据保留版本，本轮未重跑；完整双端、预算和业务仍未完成。下方为历史记录。

> **2026-10-14 相册身份/时序复试当前：**从已推送1852dda接续，只增带SLOW/FAST、帧号和循环标记的合成对照、示例测试与系统解码诊断点位；核心组件/API/锁/旧素材不变。最后修改后包90＋示例5、两处分析/bundle及两份ARM64 Android构建/验签PASS，实验手机包20263017、普通手机包仍20263014。真实Gal两份原文件SHA/结算清理PASS；vivo Gallery9.4.6.13外部有限首帧启动FAIL，内部切回确认为SLOW自身Frame2/3，但录屏中约0.1–0.2秒换色、超过有限时长仍循环，时序/结束FAIL。相同输入Android系统对照约2秒两轮并结束PASS。旧“会”截图实际GIF，不算WebP通过；文件名/变色不足以判完整回放。具体相册内部缺陷未确认，产品保存仍默认关闭，无转换/降质/fork/生产桥。见[身份报告](image-viewer-gallery-identity-report.md)、[机器证据](image-viewer-gallery-identity-verification.json)及台账currentImageViewerGalleryIdentity。11:11已归还手机/停止私有单设备ADB/删除新密钥，未改系统设置；完整平台矩阵/iOS未验，预算和业务未开发。旧证据保留版本，下方不代证当前。

> **2026-10-14 WebP复试当前：**从已推送 `d7413522` 接续，只增合成回放对照/示例测试与 nativecheckDebug 系统解码诊断，核心组件/API/锁文件不变。最后修改后包90＋示例4、两处分析/bundle与两份ARM64构建/验签PASS。真实 vivo S18：保存字节完整；相册无限WebP无需触碰可播，12秒有限WebP仍首帧静止；同一有限文件在Android系统解码对照可播两轮并结束，问题限定到这版vivo相册有限循环启动/恢复路径，内部具体缺陷未确认。左右切图后播放未确认同文件，不登记通过。产品保存仍默认关闭。相册用20263015、系统解码用20263016，普通手机包保留20263014；旧手势/权限/GIF证据保留各自版本。见[复试报告](image-viewer-webp-retry-report.md)、[机器证据](image-viewer-webp-retry-verification.json)及台账currentImageViewerWebpRetry。手机已交回、私有ADB已停止且两类临时密钥删除；本轮未改系统设置（实读自动旋转1）。上次遗留的本任务公钥本轮已精确清理并更正旧声明。完整平台矩阵/iOS未验，预算/业务未开发；无main合并/Release/部署。

2026-10-14 当前结果见[单台实测报告](image-viewer-android-device-report.md)与[机器证据](image-viewer-android-device-verification.json)。当前实际APK20263014；AV02/03/04保留原20263013物理证据，不冒称全部重跑。当前设置已恢复、私有ADB已停止；再次设备操作需新明确窗口。下方2026-10-13“未识别/全部NOT_RUN”为准备时历史快照，操作定义继续有效。

| 项 | 当前有范围结果 | 仍需复验 |
|---|---|---|
| AV01 | PASS 初始适屏/适宽顶部 | 完整格式/EXIF矩阵 |
| AV02 | 人工限定PASS | 完整多指矩阵 |
| AV03 | 严格人工复验PASS | 其他设备/iOS；首次非严格录像不计通过 |
| AV04 | 正常缩放BAND03旋转PASS；整矩阵NOT_RUN | 放大和进行中手势旋转 |
| AV05 | PASS 组切换阅读像素一致/新会话TOP | 其他缩放/组矩阵 |
| AV06 | PASS OS返回/按钮/合格物理下拉 | 快速重复完整矩阵 |
| AV07 | PASS 故障、重试、撤销 | 业务来源单列，不接入 |
| AV08 | PASS 三秒迟到来源隔离 | 完整生命周期组合 |
| AV09 | 前台GIF/WebP实际录像PASS；整矩阵NOT_RUN | OS后台/不可见与资源证明 |
| AV10 | 字体1.88和基础TalkBack PASS；整矩阵NOT_RUN | 全部反馈朗读/横屏组合 |
| AS01 | API29+直接保存不申请旧存储权限 | 新基线下核对无广泛读取权限；旧系统场景SKIP（用户移除支持） |
| AS02 | PASS 原PNG、相册显示和修复后布局 | 更多格式/设备 |
| AS03 | PASS 一份原GIF字节与人工相册回放 | 完整GIF矩阵 |
| AS04 | 原WebP字节PASS；直接打开自动播放FAIL、拖动后PASS | 相册自身入口/另一受控版本或播放器 |
| AS05 | PASS 两秒注入窗口三次点击只一次派发/媒体 | 完整连点时序矩阵 |
| AS06 | PASS 关闭后真实写入继续、旧反馈隔离 | 系统取消不承诺 |
| AS07 | PASS 两次真实文件消失错误/可再试/无媒体 | 插件返回格式错误；精确文件消失诊断未改造 |
| AS08 | PASS 当前7次原生操作结算后文件/目录清理 | 更多设备与未知结算情形 |

下面完整定义中的PASS只有完成其全部条件才可登记；当前逐子项以上述实测记录为准。产品原生保存仍关闭，iOS/MIV13/MIV14不由本台关闭。

2026-10-13。范围为独立组件示例，不接主 App。构建、宿主检查和设备结果见[本轮 Android 记录](image-viewer-android-report.md)。**用户已授予 vivo S18 空闲窗口：暂不限定，社区需要时立即停止，可配合人工核对。当前 ADB 连接列表为空，所有下列平台用例均 NOT_RUN。**仅在可确认的该单台实体手机上执行；不得操作模拟器、重启 ADB 或改动认证/社区服务。

## 设备与 APK 记录

开始前必须记录用户明确授予的空闲窗口、具体单台设备 ID/型号、Android/API/ABI、实际系统相册包名/版本、字体与读屏状态、APK SHA256/版本号/包名/证书 SHA256及被测源码摘要。不得用构建机/宿主测试填这些字段。若窗口结束或社区需要手机，停止设备操作；不重启 ADB、不停止其他服务。字体、方向和读屏设置按窗口前状态恢复。

| APK | 包名 | 保存 | 用途 |
|---|---|---|---|
| componentDebug | org.hnuhole.image_viewer_component | 默认关闭；单独传导出 define 也不能启用 | 查看/来源/生命周期/读屏/大字 |
| nativecheckDebug | org.hnuhole.image_viewer_component.nativecheck | 只有 nativecheck flavor + VIEWER_ENABLE_NATIVE_EXPORT=true 同时满足才启用 | 合成素材的真实 gal/MediaStore 与相册实验 |

两个包均使用本任务新建的测试签名。APK 实际 hash、版本、ABI与证书以构建记录为准，不使用认证签名/账号/密钥。arm64 APK 安装前须在获准窗口核对实际设备 ABI；不匹配时先重建相应 ABI。不得覆盖或清理其他会话 App。

## 查看与生命周期

每项独立填写 PASS/FAIL/NOT_RUN/BLOCKED/SKIP、时间、APK、证据路径和限制。录像要能区分一次持续接触与抬手后新接触；Flutter tester 的注入手势与实际手指操作分开标注。

| 用例 | 关联 | 操作与通过条件 | 当前 |
|---|---|---|---|
| AV01 普通/长图初始位置 | MIV02/03 | 打开 ordinary.png 与 long.png；普通图适屏，长图适宽、首帧从顶部进入；不得先居中再跳顶 | NOT_RUN |
| AV02 缩放/多指/双击 | MIV04 | 双指缩放、放大平移、双击放大/恢复、单指变双指及抬起顺序；不能误切图/误退出 | NOT_RUN |
| AV03 回顶同手势 | MIV03 | 先向下阅读长图；持续同一手势回到顶部后继续下拉，不能出现退出变换或关闭；全部手指松开后新的单指下拉才可关闭。保存完整录像 | NOT_RUN |
| AV04 旋转锚点 | MIV05/08 | 在长图中部及放大状态旋转、再旋转回来；记录阅读标记/视口锚点偏差；旋转不能给未结束手势授予退出资格 | NOT_RUN |
| AV05 组切换/阅读恢复 | MIV05 | 长图中部切到另一图再返回，恢复阅读位置；首尾不绕回；关闭后新会话长图从顶进入 | NOT_RUN |
| AV06 返回与关闭归属 | MIV06 | 分别关闭按钮、Android 系统返回和合格下拉；每次只回到调用方启动页一次，不越级 pop；快速重复开关不残留页面 | NOT_RUN |
| AV07 来源失败/重试/撤销 | MIV07/08 | “首次失败与手动重试”先失败、再恢复；模拟访问失效终止显示，旧来源/解码结果不得恢复已失效页面 | NOT_RUN |
| AV08 关闭后迟到来源 | MIV07/08 | “延迟加载与关闭隔离”三秒内关闭，立即打开普通图；等超过三秒，旧结果不得改变新页面、导航或产生未挂载回调错误 | NOT_RUN |
| AV09 动画与前后台 | MIV02/08 | GIF/WebP实际播放；切页、隐藏、后台/回前台、关闭与撤销；核对不可见播放及恢复，不能用宿主监听数量代证 Android 系统行为 | NOT_RUN |
| AV10 读屏/大字 | MIV12 | 真实 TalkBack、放大字体、小视口/横屏；按钮名称、禁用原因、当前索引、失败重试和保存反馈可读可操作，无溢出遮挡；记录实际设置与截图 | NOT_RUN |

默认设备自动化入口（仅获得窗口后）：

```text
# packages/image_viewer/example；必须指定已获准的单台设备，不使用默认设备发现。
flutter test integration_test/image_viewer_component_device_test.dart --flavor component -d <获准设备ID>
```

该入口包含长图持续手势、新下拉及错误/重试/撤销场景；它不是全部物理手指、旋转、读屏、后台矩阵。自动化通过后仍逐项完成人工场景。示例里的三秒来源延迟是故障注入，不是网络性能测量。

## 真实相册保存（单列）

只在 nativecheck APK、合成媒体、限定窗口中执行。例内所有保存使用实际 GalViewerGalleryWriter；故障注入只围绕公开 Dart 适配接口，不更改插件、不增加原生桥。`VIEWER_PLATFORM_EVENT` 日志只含阶段、操作序号、布尔状态和模式，无私有路径、图片字节、账号或底层原异常。

| 用例 | 操作与证据 | 当前 |
|---|---|---|
| AS01 权限允许/拒绝/再试 | 支持API29+。记录实际 API、Gal.hasAccess、查看不申请相册权限、保存自身媒体无需旧写入权限；核对无全图库读取。旧API28及以下拒绝/再授权流程SKIP（用户移除支持），不得用替身冒称平台权限PASS | NOT_RUN |
| AS02 普通原文件保存 | 保存合成普通图；分别记录插件结算、实际 MediaStore 新项、完整文件与相册显示。保存成功文案不代证后两项 | NOT_RUN |
| AS03 GIF 原格式 | 保存 animation.gif；取回本次明确生成的新项原文件，核对下面的 SHA/934字节/3帧/80,120,200ms/rawLoop2，再在实际系统相册播放并单列记录 | NOT_RUN |
| AS04 动态 WebP 原格式 | 保存 animation.webp；取回原文件，核对 SHA/290字节/3帧/80,120,200ms/rawLoop2，再实际相册播放。格式成功但不播放不得自动转 GIF/首帧或降低质量 | NOT_RUN |
| AS05 连点 | 打开“保存连点与关闭竞争（延迟适配器）”，两秒适配器延迟内重复点击；按钮忙态/禁用且同一操作只一次 adapter/native dispatch、只生成一个媒体项。延迟是注入，不是原生延迟量测 | NOT_RUN |
| AS06 保存中关闭 | 同一延迟场景点击保存后立即关闭并打开另一图；已进入适配器的操作可能继续到真实系统写入，必须记录是否实际写入；晚结果不能发布旧/新页面反馈或重复导航。不把关闭宣称为系统取消成功 | NOT_RUN |
| AS07 临时文件消失 | “临时文件消失（真实 Gal 错误）”只删除本操作自有文件后调用真实插件；记录实际错误分类、无虚假成功、忙态恢复/可重试、无额外媒体项及自有目录清理。这是故障注入，不是系统随机故障复现 | NOT_RUN |
| AS08 结算后清理 | 成功/原生失败/关闭后观察 settledCleanupObserved：fileExists=false、directoryExists=false；保存尚未结算时不得提前清理正在使用的文件。未知结果不能自动重复导出 | NOT_RUN |

gal2.3.3 Android 源码 `hasAccess(false)` 在 API29+ 返回 true；此组件使用直接相册写入，不请求读取全部相册。若设备为这些版本，权限拒绝项登记 **SKIP（该设备/路径不申请此权限）**，API28及以下已按用户决策移除支持范围；不强行索取广泛存储权限、不使用账号数据、不把本单台设备验收泛化成所有 Android 版本。

预计只有在窗口、操作者和相册核对步骤齐备后才使用：

```text
flutter test integration_test/image_viewer_component_device_test.dart --flavor nativecheck -d <获准设备ID> --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
```

首次权限对话若使组件 lease 失效，先如实记录首轮行为，再返回查看后主动重试；不能把首次失败隐藏掉。默认原格式路径不转换。未知结果先检查相册，不重复点击盲目导出。

## 测试素材与文件完整性

素材全部为仓库合成图片；实际文件应与 `example/assets/fixtures/manifest.json` 核对。

| 文件 | 原始 SHA256 | 大小/动画 |
|---|---|---|
| ordinary.png | 6cc1d099a6d3ab59f6abbfcda73a023212e605623a768fe177d11f630cf2d964 | 3656字节，640×480 |
| long.png | 69269d9cd174e1be00a84efecc1b9a01b9150ba4dae8b41816359ae13749575b | 17659字节，480×2400 |
| animation.gif | 1343ba962a5e4754481cbd1227922a09445ad59819da0e17cadbec810392369c | 934字节，96×72，3帧，80/120/200ms，rawLoop2 |
| animation.webp | 8b8b45e3f971e60b42ff0d45cc01aada69ff7856744500dfb655930595bfa139 | 290字节，96×72，3帧，80/120/200ms，rawLoop2 |

媒体查询、取回与清理仅针对本次已确认的新项（包名/时间/文件名或确切 URI）；不扫描、导出或删除用户其他相册。记录导出原文件 SHA256、长度、帧时序/循环与实际相册播放器结果；相册缩略图不够。原始 SHA 一致即可证明字节完整，回放行为仍需单列观察。有限/无限循环其他样本可补，不把四份素材宣称为完整格式矩阵/资源预算。

本台验证不关闭 iOS、MIV13 手机资源预算或 MIV14 业务接入门槛。发现库平台问题时保留最小合成复现、实际版本和影响范围；大规模 fork、解码器或大范围原生桥仍需先报告方案与成本。
