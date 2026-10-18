# 主 App 帖子图片：S18 真机联调交接

2026-10-15，Asia/Shanghai。结果为 **PASS_SCOPED_ANDROID_BUSINESS_DEVICE**：真实主 App 的原生选图、原图草稿、九图上传/补传、发布、受保护查看、原格式相册保存、失败编辑重试及访问失效已取得本轮 S18 证据。修复了一处发布核对成功后仍显示旧错误提示的问题。手机窗口已结束，不需要继续配合；这不是全 Android 机型/相册、iOS、完整 App 或生产验收通过。

## 固定版本与修改

- 独立目录 `E:/Hnuhole-post-media-joint-20261015/repo`，分支 `codex/post-image-integration`，origin 为 `zewbby/HnuHole`。
- 本轮起点 `c1b26ea27ce6cf567ab41dc44de8f0700799ea2c`；修复实现提交 `fd2e4c04f48b29ddda0142660188988c4a655f5f`。最终交接 HEAD 以包含本报告的提交及 `git rev-parse HEAD` 为准，避免在提交中自引用。
- 本轮产品修改只在 `apps/mobile/lib/src/posts/post_controller.dart`：错误提示绑定原 command；对应权威结果持久化后清除旧提示，仍未知时保留，其他操作的后来错误不被误清。账号授权窗口改变时一并清除绑定。
- `apps/mobile/test/post_controller_test.dart` 增加上述三项回归；`tools/post-media-android/native.init.gradle` 支持受限的八位测试版本号，便于分辨修复包。其余变更为本轮交接记录。
- 未修改认证插件、图片引擎、Go、SQL、上传协议或锁文件；未合并 main、发布 Release 或部署。Android 保存沿用已经默认开启的组件实现，本轮没有再次改变其默认值；iOS 不因 Android 通过而开启。

实际设备为 vivo S18/V2323A、Android15/API35、ARM64。仅复用用户明确释放的既有物理设备连接服务34881，直接使用其协议，没有启动、停止或重启 ADB。5037的模拟器候选被守卫拒绝，未对其安装、写入或停止。测试签名为本任务新 key，证书 SHA256 `85c8fc2812395423b7d474c226e744e15f65392c770cbadb003af66afed0af8d`。

| APK | 实际版本 | 字节数 | SHA256 |
|---|---|---:|---|
| 初始主 App | 20263115 | 98449172 | `ae589d166734eb1888bc03c41d4cee8f49797ee6969f40cf4abaa6614c48892f` |
| 原图存储 probe | 20263115 | 100051228 | `af27b986b3be2ca9f74d688daa5b7ffc1cfcfeaccb98e4711fee013aa037b193` |
| 修复后主 App | **20263116** / `0.1.0-media-android-20263116` | 98443748 | `451f87f0a19ed920795c9bf7fdd2d89c1adb1fefba62f32d3d2db6c9b5bd257c` |

主 App 包名 `org.hnuhole.post_media_android`，probe 为其 `.probe` 包。minSdk29/target36、Debug、v2签名已实际核验，安装后的 base.apk 摘要与材料一致。Flutter engine 为 ARM64，插件另含其他 ABI，不称纯 ARM64 APK。本轮没有构建主 App Release。

## 本轮实际设备结果

详细原始小型记录、时间、版本和源摘要见[机器记录](post-image-android-device-verification.json)中的44份设备记录及清理回执。以下 `PASS_SCOPED` 只表示该行写明的范围，不补齐未执行子项。

| 病例 | 实际结果与边界 |
|---|---|
| PMA01 启动/链路 | PASS。实际 `lib/main.dart`、原生端口、私有 CA 验链与主机名校验、独立真实 C/V/PG；两套合成账号，未使用真实账号。 |
| PMA02 原图存储 | PASS。真实 PostStore→business vault/Keystore/no_backup，9原图含跨256KiB chunk；write/read进程PID不同，摘要一致，错摘要/异账号拒绝，probe清理与关闭后拒绝。不是硬件 key 物理擦除证明。 |
| PMA03 Photo Picker | PASS_SCOPED。实际取消不改草稿，选择本任务合成图。本轮没有权限弹窗，权限拒绝按实际记 N/A，未重引入旧存储权限或 API28 以下设计。 |
| PMA04 九图编辑 | PASS_SCOPED。实际长按拖动交换顺序、稳定ID保持、移除后补选、空正文图片帖。9/9时添加入口隐藏；未伪称实际选中第十张后被拒绝。补选曾选到重复08图，原文件 SHA 校验拦住发布，改选01后通过。 |
| PMA05 恢复/中断 | PASS_SCOPED。杀本主 App 后，9张加密原图草稿和顺序恢复；后续实际上传及相册文件摘要证明恢复的是原字节。选图中断后保留8张，取消旧 Picker 后再补选，未把无绑定选择导入账号。不是所有 OS 完成结果重投路径的穷举。 |
| PMA06 真实上传/公开 | PASS。客户端九图清单、SQL payload、系统相册文件逐项长度/SHA/顺序一致。SQL先8项验证、0公开，最后9项验证才公开。 |
| PMA07 丢响应/补传 | PASS。丢CREATE响应后杀进程重启，仍只有一次原命令；PUT前断连、成功收据丢失后，继续上传只补真正缺失的一张，成功项不再发送。 |
| PMA08 失败编辑重试 | PASS。正式 operator 短限制使v1 FAILED，旧图片记录清除；原图仍可编辑，原身份/通道固定，同一 task 的v2实际上传公开、正文为编辑后的 `retry-2`。20263116再次丢响应并核对终态，旧错误提示已自动清除，无需重启。 |
| PMA09 查看/手势/位置 | PASS_SCOPED。用户确认主 App 双指缩放/平移、同一次回顶不退出、抬指后新下拉退出“正常”。修复包使用真实 Android WindowManager 切2400×1080横屏再回1080×2400竖屏，2倍缩放与归一化锚点保持，前后切图位置恢复；系统旋转状态已恢复。该自动检查不冒称再次手动验证物理旋转传感器。 |
| PMA10 保存/竞争 | PASS_SCOPED。实际主 App→受保护原图 resolver→Gal→MediaStore 保存9份原格式，三连点只写一次；原图响应持有期间关闭后，迟到结果不写相册、不显示成功；组件临时目录结算归零。已派发原生写入后的关闭、故意临时文件消失沿用未修改组件的[历史设备范围](image-viewer-android-saving-report.md)，本轮主 App 未重新注入。 |
| PMA11 动画回放 | PASS_SCOPED。9份保存文件 SHA/长度与原图一致，无 GIF 转换、降质或改循环。Fossify Gallery1.14.0(29)实际打开本次 MediaStore 文件，无触屏按0.5秒取样：GIF/无限WebP自动RGB切换，有限WebP约2秒/色、两轮后停蓝。 |
| PMA12 失效/隔离 | PASS_SCOPED。取消任务后SQL清除且不公开，原图另存草稿可恢复；删帖9 payload清除，清单/原图C404，迟到响应不保存；退出后旧会话C401，当前store和个人内容解除；第二个实际合成账号及新页面无前账号草稿/个人帖子。真实60秒租约到期后不可访问，可重新读取。不是账号注销、Passkey或完整认证专项。 |
| PMA13 输入/业务控件 | PASS_SCOPED。用户用实际中文IME输入“图片真机验收”；本轮选图、计数、上传进度、失败、补传/重试等控件实际可操作，并读取原生语义。按用户要求不重复旧组件 TalkBack/大字全套，不将 UI 树读取写成新一轮 TalkBack 人工通过。 |
| PMA14 资源观察 | PASS_SCOPED_OBSERVATION。约1MiB九图功能完成，临时目录归零。另一次Debug单点PSS371611KiB/RSS519860KiB、自有cache3892KiB；不是峰值、无泄漏或最大预算结论。九张10MiB及生产存储资源预算仍未验。 |

vivo相册9.4.6.13已有的有限WebP首开/计时/循环异常保留在[相册兼容性记录](image-viewer-gallery-compatibility-report.md)。本轮没有重测它，也没有证据把原因归为“过老版本”，不把它计为本轮通过；Fossify的实际回放与原文件完整性单独登记。没有修改厂商相册、大规模fork、解码器或原生桥。

## 修复后的宿主与构建检查

运行根为本任务独立SDK、Pub/Gradle/profile/temp；没有升级共享SDK或下载大型缓存到C盘。下列检查均在最后源码修改后实际执行，精确参数、输入摘要和日志SHA见机器记录的 `checks`。

| 命令/检查 | 本轮实际结果 | 日志名（日志根见下） |
|---|---|---|
| `flutter test --no-pub --reporter=expanded test/post_controller_test.dart test/post_composer_media_test.dart test/post_media_repository_test.dart` | **69 PASS**，含3项旧错误提示回归 | `native-window-controller-regression.log` |
| `flutter analyze --no-pub` | **0问题** | `native-window-analyze.log` |
| `flutter build bundle --debug --no-pub` | PASS | `native-window-bundle.log` |
| Gradle9.3.1 `--offline --no-daemon --max-workers=2 ... assembleDebug -DpostMediaVersion=20263116` | PASS；301项任务、33执行，77.51秒 | `native-window-main-build.log` |
| `apksigner verify --verbose --print-certs`、`aapt dump badging` | PASS，v2/版本/包名/API身份 | `native-window-apk-signature.log`、`native-window-apk-identity.log` |
| `E:/acanda/python.exe -X utf8 -B tools/post-media-android/test_preparation.py` | **15 PASS** | 机器记录中保存实际命令、计数和exit0 |

日志根 `E:/Hnuhole-post-media-android-20261015/logs/`。完整mobile375、后端244、Python4/OpenAPI6等仍为[上轮固定源码结果](post-image-joint-report.md)，本轮未重跑，不重新登记为当前通过。构建的Gradle弃用警告保留，当前exit0；没有升级Gradle或SDK。

组件API与输入/生命周期契约沿用[包README](../../packages/image_viewer/README.md)：稳定唯一内容ID；调用方提供已授权来源及完整原文件；组件不收账号/Bearer/密码/恢复材料，不建长期私有图片磁盘缓存；关闭/失效是终态，迟到加载及保存反馈隔离。业务层负责原生加密草稿、受保护C读取和最长60秒终止租约。测试驱动仅在内存使用本任务合成会话做C404/401探测，没有导出token。

## 窗口结束与材料状态

字体1.0、方向锁0、无障碍关闭均已核回原值；本轮只临时切换系统显示旋转，未开启TalkBack。两个合成会话均退出，两个自有测试包已停止；仅撤销本轮建立的43057/42161 reverse，并移除自有手机临时APK/UI文件。按集中SOP保留手机上的两个测试包、9张合成来源和10份本任务相册输出，未删除手机媒体或操作其他包。

自己的C/V/watch/PG已停止，Linux专用根 `/home/hnuhole/post-media-joint-android-20261015` 已删除，包括临时数据库、CA/Gate及私钥。首次清理遇只读Go模块目录，确认全为本任务当前用户所有后，仅在该根内补目录写权限并清理成功。

**Windows清理部分阻断。**自动审批先后拒绝专用SDK/缓存的批量清理，以及缩小为明确敏感文件/测试key/APK/截图的清理，均只返回 `blocked by policy`，未给更具体原因；这些命令没有执行，未换用其他方式绕过。`E:/Hnuhole-post-media-android-20261015` 中SDK/cache、APK、私有合成账号材料/测试签名和截图仍保留，private/profile的受限ACL已只读核对；仓库内忽略的构建制品也未冒称已清。脱敏记录与测试辅助脚本备份已保留，秘密不入Git。旧的“空库/服务待启动”准备清单已经失效，不能直接重用它恢复旧会话。

## 独立剩余工作

1. iOS原始选图适配仍未实现，现图库路径会重编码，入口继续关闭；需要macOS/Xcode、iOS设备后完成原始资源读取、Keychain/原生构建、权限与相册回放，不能只写“剩测试”。
2. 最大九图内存/解码/并发/磁盘预算、生产SQL原字节的配额/WAL/备份删除与限流，以及存量正式Goose升级仍需专门环境和预算验收。本轮单台S18的小素材通过不覆盖这些门槛。
3. 评论/私信图片消费者尚未实现；正式签名/发布、部署与完整认证/社区验收继续由对应任务负责。当前分支正常提交推送，不合并main或发布。

交付脱敏复核：全文件扫描曾命中台账历史段落已有的设备标识；核对 `c1b26ea..2f59bb2` 的全部新增行，账号秘密、恢复码及设备明文新增匹配为0。首次Shell未在检查错误后停止，交接提交已推送后完成本次核查；后续Git动作使用失败即停止的调用，未改写其他任务历史或强推。
