# 独立图片组件宿主实现交付

2026-10-12（Asia/Shanghai）。本轮完成可独立实现和宿主验证的组件封装；原生门槛挂起，不宣布 Android/iOS 完整通过。M1 技术样例继续保留为历史研究，M1 双端技术关、M3 正式验收和 M4 业务接入未完成。

## 版本与隔离

- 仓库 `zewbby/HnuHole`，分支 `codex/image-viewer-component`。
- 本次 `git ls-remote` 和独立 clone 的实际起始 SHA：`7ebce73fbcfbd27c5968cc2813f5eea0ca3590bf`。最终 HEAD 同一 SHA；修改均未提交。未提交文件和逐文件 SHA256 见 [本轮记录](image-viewer-component-host-verification.json)。本轮没有提交、推送、合并或部署。
- 独立工作区 `E:/Hnuhole-image-viewer-component-20261012/repo`；日志在同级 `logs/`。用户入口是无提交的外层仓库，认证目录存在未提交修改，均未切换、覆盖或清理。`preflight.md` 保留只读核对。
- 认证引用现成 SDK 和旧图片任务 Pub 缓存，不能直接执行或写入。本轮实复制 Flutter/Pub，并将生成的 package config 重定位到任务私有根；SDK/Pub/TEMP/用户配置/Android user/日志全部独立且无链接。SDK 版本 Flutter 3.47.5 / Dart 3.13.4，SDK SHA `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`。工具副本的 `bin/cache` 可独立写入。
- baseline bundle 首次因私有 SDK 定位 Android SDK 失败，随后只读盘点并实复制 licenses/platforms/build-tools 的最小部分，同命令通过。没有复制或调用 ADB、模拟器、设备，没有原生构建、NDK/JDK/Gradle 下载或工具升级。保存原始 FAIL 和 retry PASS；bundle 仍只证明 Dart/kernel/资源编译。
- 工具启动器 `E:/Hnuhole-image-viewer-component-20261012/run-flutter.ps1` 阻止设备、原生 build、升级及非严格离线 Pub 命令，禁 artifact 下载。清理只限本任务实际创建的缓存/产物，结果单列在本轮记录。
- 最终依 AGENTS 收尾规则清理本任务创建的 SDK 副本、Pub/profile/TEMP 缓存和忽略的构建生成文件，共 4,233,381,767 字节；保留独立 repo、锁文件、合成图片、源码、测试、启动器和小型日志。`logs/component-cleanup.json` 列出每个已解析的绝对目标及不存在的后验；源 SDK、旧共享 Pub 缓存和认证目录均保留。复验需重新准备独立工具。清理后重新核对被测包 SHA256 清单、锁和修改范围，源码快照不变。

## API 与责任

公开库：`packages/image_viewer/lib/image_viewer.dart`。详细用法见 [包 README](../../packages/image_viewer/README.md)。

| 入口 | 契约 |
|---|---|
| ViewerItem / ViewerItem.provider | 稳定媒体 ID、当前来源加载器、可选说明/完整原文件 resolver、保存许可；同 ID 同内容版本 |
| ViewerSource | 调用方已授权 ImageProvider + 有限正整数的解码尺寸；真实首帧尺寸一致后才 ready |
| ViewerController | 非空有序组、有效初始索引、组内唯一无周围空白 ID；immutable 组；select/retry/replaceItems/invalidateAccess/close/dispose |
| ViewerSnapshot / ViewerFailure | 当前会话的索引、枚举状态及代次；无 provider、URL、私有路径或原异常；生产模式输入校验 |
| ViewerReadingPosition | 相对当前布局基准的缩放与视口中心归一化锚点；按稳定 ID 在本会话保存 |
| HnuImageViewer | 有界视口中的交互/UI；onChanged 合并为每帧最新快照，onClosed 绑定期间仅一次；调用方拥有 route 导航和父页面位置 |
| ViewerOriginal / ViewerGalleryWriter | 完整原格式 bytes 或绝对文件路径；权限/系统写入适配接口；bytes 不可变快照、调用方原文件不删除 |
| ViewerSaveCoordinator / ViewerSaveResult | 单保存忙态、逐 async 边界 lease、结构化结果/清理状态；默认没有原生 adapter，显式 GalViewerGalleryWriter 才启用 |

只加载并渲染当前图片，失败仅影响当前图，显式重试。会话/选择/尝试代次及 source identity 隔离迟到来源和解码结果；替换整组清阅读状态，重试同内容保留锚点。close、invalidateAccess、Widget 撤下为终态，重开使用新 controller；同一个 controller 不能同时绑定两个 viewer。组件不接收账号、Bearer、密码、恢复材料，不建立长期私有缓存；调用方负责实际授权、来源缓存 key/策略和真实读取取消。回调只传脱敏状态，调用方 ID/说明不得包含敏感材料。

普通图适屏居中，长图适宽并从顶部进入；基准随布局计算。回顶同手势不获得退出资格，全部松手后新单指下拉才可关闭。缩放/双指/阅读方向与组内分页沿用 extended_image 与 Flutter 公共 API 的集中适配，未 fork、未自研图片引擎/解码器/原生桥。

布局变化按相对缩放和归一化中心锚点恢复；只声明本轮 widget 布局变更证明范围，真实设备旋转与多指组合继续待验。前后台与祖先 TickerMode 合并：离页/隐藏/后台不调度不可见动画，旧来源结果废弃。Offstage 嵌入需调用方同时设置 TickerMode(false)。

保存许可与相册权限分开；禁止保存不会触发完整来源/权限/写入。只有明确点击后才取得完整原文件，GIF/动态 WebP 不转换、不降为首帧、不静默降低质量。结果未知不自动重写。关闭/换组/换图/后台/失效发生在可控写入前时阻断后续阶段；adapter 被调用后，gal 内部可能再次请求权限并写入，组件不能承诺取消。晚结果可结算，但不能污染旧/新 UI。只在 adapter Future 结束后清理自有临时文件；清理失败保留真实写入结果及独立重试清理入口，不重复导出。

## 本轮检查与修复

命令都由上述隔离启动器执行；每条日志旁 `.json` 记录命令、cwd、exit、HEAD、锁文件及被测源码前后摘要。最后检查的源码在命令执行期间保持稳定。旧 2026-10-10 结果未作为本轮通过依据。

| 范围 | 实际命令 | 本轮结果与日志 |
|---|---|---|
| baseline 包/示例 | flutter pub get --offline --enforce-lockfile；flutter analyze --no-pub | PASS，baseline-package/example-pub-get 与 analyze |
| baseline 测试 | flutter test --no-pub --machine --concurrency=1 | PASS，原 36 项；baseline-host-tests.log / baseline-host-test-results.json |
| baseline bundle | flutter build bundle --debug --no-pub | 首次 FAIL（隔离 SDK 寻址），retry PASS；baseline-example-bundle[-retry].log |
| 最后包/示例分析 | flutter analyze --no-pub | PASS，均 No issues found；final-package-analyze-complete.log / final-example-analyze-complete.log |
| 最后包宿主测试 | flutter test --no-pub --machine --concurrency=1 | PASS，88/88，0 FAIL、0 SKIP；final-host-tests-complete.log / final-host-tests-complete-results.json |
| 最后示例宿主测试 | flutter test --no-pub --machine --concurrency=1 test/component_example_test.dart | PASS，2/2，0 FAIL、0 SKIP；final-example-tests-complete.log / final-example-tests-complete-results.json |
| 最后 bundle | flutter build bundle --debug --no-pub | PASS，exit 0；final-example-bundle-complete.log |

最后五项都针对同一包源码快照 `7846f16efea2ed8d81eee59349fc5cb96d34393f2ebad937279a5fcb8f45cd28`，运行期间没有源码变化。88 项由原 36 项、新增旧保存清理回归 1 项、组件契约 29 项和新保存协调层 22 项组成；另 2 项验证示例的实际 typed route 关闭、手动重试和失效。每个测试名称/结果及全部修改文件列于本轮机器记录。

两份锁文件保留，无版本/来源漂移。SHA256：包 `00ac99d693f003b46111d24e18a233741aedfd3501569130d57d731ca192fb81`；示例 `9a7de0b094b07456d44016212168f2f5890e5a74d0bf4f708d77db6c51c95a24`。

实际复现的旧保存缺陷：系统写入完成后 owned 临时目录已经消失，finally.delete 抛 PathNotFoundException，覆盖 written 且 busy 卡住。`regression-m1-cleanup-before.log` 记录 FAIL；修改后聚焦/全量重跑，忙态必重置。新服务将清理失败与系统结果分开，并提供只清理不重写的 retryCleanup。

新封装首轮聚焦检查中大字语义 label 断言 FAIL：当前 Flutter 的 IconButton tooltip 在独立 tooltip 属性，不是 label。正式按钮改为唯一语义 label/action，保留触摸 key/tooltip；最后测试及截图/语义 bounds/action 单列证明范围，不能当 TalkBack/VoiceOver 实测。审查还收口 source/token 同层快照、旧解码帧隔离、保存 adapter 替换 lease 和导航归属，回归覆盖这些实际状态竞争。

新增测试的前次执行还暴露测试 harness 的文件/asset IO 等待和 SemanticsHandle 释放问题：首次全量被精准终止本任务的 tester/compiler 进程，后次有未释放 handle 断言；示例首次因 fake clock 下 asset IO 未完成而失败。已改为有界 runAsync 等待及 finally 释放，最终完整重跑通过。失败、中止和进程归属记录均保留。大字截图是 Ahem 测试字形的软件渲染，只证明布局与语义动作/尺寸；真实字体、系统读屏和设备图稿未验。

旧动画测试自动写历史证据的副作用已移到任务日志；baseline 生成内容与原证据逐字节相同，保留历史文件。本轮启动器的空环境变量清除问题也已修复，工具失败日志独立保留，未计作产品测试失败。

## 逐项目标与证明门槛

| 本轮目标 | 实现 | 宿主证据 | 仍未验/未开发 |
|---|---|---|---|
| 输入与稳定 ID | 已实现，release 校验/不可变组/实际尺寸核验 | 输入、指定索引、单图/重复 ID、错误尺寸 | 全格式/EXIF 矩阵及手机资源上限待补 |
| 来源、失败、重试 | 已实现，current-only/脱敏失败/手动重试 | 损坏/异常、切页换组旧帧/来源隔离 | 调用方真实受保护来源属于 M4，未开发接入 |
| 阅读/旋转锚点 | 已实现，会话按 ID 保存相对缩放/归一化中心 | 切图恢复、布局变更 | 真实旋转、多指触摸与系统配置待验 |
| 生命周期/访问失效 | 已实现，终态会话/lease/TickerMode | 后台/隐藏/撤销/卸载/旧回调与动图监听 | Android/iOS 实际系统后台待验 |
| 按钮、读屏、大字 | 已实现，首尾/忙态/禁用原因/返回/语义动作 | 320 小屏 3×文字、按钮动作/截图与语义 | TalkBack/VoiceOver/设备安全区/图稿评审待验 |
| 权限、失败、保存/关闭 | 协调层与 gal adapter 已实现，原生启用挂起 | 22 项新保存替身、13 项旧保存含修复回归；UI 忙态/晚反馈 | 真实权限/权限对话 lifecycle、原生错误/关闭竞争、相册完整性/回放待验 |

最终通过数为包 88 项、示例 2 项，仅限宿主证明范围。所有完整 MIV 平台验收仍 NOT_RUN，IV01 不登记正式完整 PASS。资源/超大媒体的手机产品上限尚未固定，MIV13 为部分试验/待开发设备预算；MIV14 三类业务接入未开发。

## 原生构建、系统相册与真机复验

本轮不运行手机/模拟器/ADB，不占用认证服务或设备。下述命令是待验步骤，不是本轮已执行命令。

| 门槛 | 当前状态 | 解阻条件与复验 |
|---|---|---|
| Android 原生 APK | NOT_RUN；任务只有宿主 bundle 所需 SDK 子集 | 准备独立 Android SDK/JDK17、Gradle9.3.1/AGP9.1.0/Kotlin2.4.0缓存和独立 Gradle 用户目录；example 执行 flutter build apk --debug --no-pub；记录实际构建工具/exit/log/源码摘要 |
| iOS 原生链接 | BLOCKED/NOT_RUN：本机 Windows | 独立 Mac/Xcode、CocoaPods/Flutter 缓存；example 执行 flutter build ios --debug --no-codesign --no-pub；安装真机另需独立签名 |
| 系统权限与原生保存 | 已有适配代码，实际 NOT_RUN | 两端专用设备，逐项允许/拒绝/撤销/首次授权/空间不足/格式失败/连点/关闭或后台竞争；核对首次权限对话 inactive/resumed 是否使操作失效，必要时用户回到查看后再次主动保存 |
| 文件完整性 | NOT_RUN 原生输出 | JPEG/PNG/GIF/WebP 合成来源导出，回收原始导出文件，比较 SHA256/帧数/时长/有限无限循环；不得仅看相册缩略图 |
| 系统相册回放 | NOT_RUN；GIF/WebP分别记录 | 实际目标 Photos/Android 相册打开并观察完整动画；记录 OS、相册版本、导入结果、完整性和回放三份独立证据 |
| 真机交互 | NOT_RUN | 在另外明确授权的设备执行新组件 integration_test/image_viewer_component_device_test.dart，再人工核对双指/双击/回顶全过程/旋转/读屏/大字/快速切图/真实前后台及重复开关 |

新组件设备入口（在 example）：

```text
flutter test integration_test/image_viewer_component_device_test.dart -d <专用设备ID>
# 专门安排权限操作者及导出/相册核对后，才启用原生合成图片保存实验：
flutter test integration_test/image_viewer_component_device_test.dart -d <专用设备ID> --dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true
```

默认不导出。旧 M1 设备入口保留原 M1_EXPORT_FIXTURES 开关，不代证新组件。gal 2.3.3 iOS 文件导入强制解包风险未被修复或设备复现，本轮无法通过 Dart 替身证明不会崩溃；先核对目标格式导入，若出现实际缺口，再报告最小公开 API 替代/成本及必要性。条件动画 GIF 未批准/未启用；仅在原格式实际回放失败后再评估质量与手机预算，不擅自扩大为 fork、解码器或原生桥。

主 App、认证插件、Go、SQL、上传、业务 API 均未修改。B06/B07/B09/X05 只保留未来接入关联，不能把组件宿主证据算成业务/认证验收。
