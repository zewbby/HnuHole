# 主 App 帖子图片 Android 集中验收

> **2026-10-15 本轮S18窗口已结束。**实际结果为[PASS_SCOPED_ANDROID_BUSINESS_DEVICE](../../docs/design/post-image-android-device-report.md)，[机器记录](../../docs/design/post-image-android-device-verification.json)逐项说明PMA01–14范围。源码修复fd2e4c0，最终主App Debug20263116。自己的手机映射/临时文件、App及后端服务已收回，Linux专用库/私钥已删除。Windows材料清理被自动审批拦截，SDK/cache、APK及受限private/profile内的合成材料仍在；不能把原空库、旧源码清单和已结束窗口用于下一次测试。以下保留准备时说明和SOP，所有NOT_RUN为当时状态，以本轮机器记录为当前结果；新窗口先重新核材料/归属/签名与信任，不自动恢复旧会话。


准备阶段只做非手机准备。当时没有运行 ADB、读取设备、安装/启动App或修改手机设置；社区会话占用手机期间不得执行下面的设备步骤。范围为当前主App的帖子图片链路，不接管认证/社区会话的环境、Passkey验收或设备任务。最低Android10/API29，不准备旧系统适配。

## 固定材料与离线预检

本任务源码：`E:/Hnuhole-post-media-joint-20261015/repo`，分支 `codex/post-image-integration`。保留的验收包、原图、测试签名与独立同版工具在 `E:/Hnuhole-post-media-android-20261015`；Linux后端根 `/home/hnuhole/post-media-joint-android-20261015`，WSL磁盘在E盘。源工作区/其他任务缓存不修改。当前用户要求准备好等待配合，因此临时保留本kit和后端材料，验收结束再只清本任务资源，不将“已删除APK/密钥”交接为可用。

```powershell
& E:/acanda/python.exe -X utf8 -B tools/post-media-android/check_ready.py `
  --kit E:/Hnuhole-post-media-android-20261015
```

此命令只读本地文件，不建socket、不运行任何设备工具。核APK/签名身份、九图/固定输入/源码散列、后端已停止证据、TLS叶证书至少剩30分钟。任何摘要变更或证书过期均停止现场操作，先重建并复验。`window-plan.json`是未提交的本机材料清单；新提交的文档不会使已编译产品源码失效。签名不是认证签名，两个本任务包共享本kit新生成的调试key；不得拿它用于发布。

- `artifacts/main.apk`：`org.hnuhole.post_media_android`，显示“HnuHole 图片业务验收”，真实 `lib/main.dart`，已固定专用C/V loopback HTTPS和公有开发CA；不含控制token、账号或私钥。
- `artifacts/probe.apk`：`org.hnuhole.post_media_android.probe`，显示“HnuHole 原图存储探针”，只访问自己包内的合成业务scope；不读主App/auth vault，不连接C/V，不证明Photo Picker或相册行为。
- 两包versionCode `20263115`，versionName `0.1.0-media-android-ready`，API29+，Flutter ARM64 engine；插件另含其他ABI，不称纯ARM64包。
- `fixtures/`只有9张带编号的合成原图及散列，约1MiB。01 PNG约680KiB，跨多个256KiB加密chunk；03 JPEG含EXIF6；04长图有TOP/BAND00–11；05 GIF和07 WebP无限循环；06 WebP每帧2秒、两轮后停蓝。生成原文件不等于对用户输入转码，组件与上传保存仍保留原字节。

## 不接手机即可复验的入口

`build-tool.ps1`强制本kit owner、独立物理SDK/工具包依赖/Pub/Gradle/profile/temp；拒绝devices、设备test、install/connected/stop/clean等命令。仅使用已有匹配工具与锁依赖，不升级认证SDK、不自动安装工具链。Gradle及其弃用警告保留。

```powershell
$kit='E:/Hnuhole-post-media-android-20261015'
& ./tools/post-media-android/build-tool.ps1 -KitRoot $kit `
  -WorkingDirectory E:/Hnuhole-post-media-joint-20261015/repo/apps/mobile `
  -LogName pub-recheck -Tool flutter -ToolArgs @('pub','get','--offline','--enforce-lockfile')
$env:POST_MEDIA_ANDROID_FIXTURES="$kit/fixtures"
& ./tools/post-media-android/build-tool.ps1 -KitRoot $kit `
  -WorkingDirectory E:/Hnuhole-post-media-joint-20261015/repo/apps/mobile `
  -LogName fixtures-recheck -Tool flutter `
  -ToolArgs @('test','--no-pub','--reporter=expanded','integration/post_media_android_preflight_test.dart')
$env:POST_MEDIA_PREP_TEST_ROOT="$kit/temp/prep-tests"
& E:/acanda/python.exe -X utf8 -B tools/post-media-android/test_preparation.py
```

首次 `lab.py prepare`会创建全新私有PG、正式Goose/grants/真实C/V和固定Pillow校验器；不能对已有state重跑prepare。`rehearse`实际启动/核空库/CA/控制鉴权后finally停止，仅操作自己的PID与PG目录。本机已保存的Lab不再创建或reset库。

```powershell
wsl -d HnuHole-Ubuntu-24.04 -u hnuhole -- python3 -B `
  /mnt/e/Hnuhole-post-media-joint-20261015/repo/tools/post-media-android/lab.py rehearse `
  --recover-empty --root /home/hnuhole/post-media-joint-android-20261015
```

`--recover-empty`是明确调用正式operator签名恢复，不是跳过Gate；账号/OTP/posts任一非空便拒绝。准备时发现V Gate停机后为FROZEN，因此未使用静默恢复。后续有账号的lab只允许通常的renew，遇冻结先核原结果并按正式恢复/新代次登录契约处理，不能删库、改SQL或自动恢复旧会话。

## 手机释放后一次执行

本轮不询问/占用手机。对方会话明确释放且用户给出继续窗口后，使用已释放的现有连接；不启动/重启ADB、不改共享USB key、不操作对方包、服务、reverse/forward或设置。再次只读核设备型号/Android/API/ABI和既有连接归属，若offline/社区重新占用立即停设备操作；不重启服务。候选设备为历史S18，实际设备与版本要在新窗口核对，当前不预填通过。

1. 运行离线预检，启动自己的后端：上方命令把 `rehearse`换为`serve`。未使用空库可明确加`--recover-empty`；已有账号不得加。保持进程终端，结束时Ctrl-C，脚本finally只停自己的进程/PG。不要保持服务占资源等待未知窗口。
2. APK已有固定C/V端口，见`private/build-defines.json`。只对这两个端口建立自己的、无覆盖的USB reverse，先查现有映射，冲突就停止。控制端口不reverse给手机，操作员从Linux私有配置读取token。TLS继续验链/主机名，无系统CA安装、无明文HTTP或信任任意证书。
3. 安装前只读核本任务两个包是否存在；有未知签名/摘要的同名包就停止，不覆盖、不卸载、不清数据。仅安装本清单SHA对应APK。把9张图放入 `/sdcard/Pictures/HnuHoleMediaAcceptance20261015/`，逐文件核SHA并只扫描本文件夹，不浏览用户照片。
4. 先自动跑独立probe三个阶段，再用正常主App做业务。合成注册/OTP由本lab捕获；账号材料只在私有目录/手机处理，不输出Bearer、密码、恢复材料，不用真实账号。系统Passkey及认证专项由其他任务负责。
5. 按下方病例集中配合，先操作员可自动核的部分，再请用户一次做实际选图、中文键盘和手势/相册观察。不重复已完成的独立组件TalkBack全套；新业务控件的证据单独登记。每个病例只记录实际观察，失败保留现场，定位、最小修复和受影响回归后重试。
6. 结束只收本包私有witness、合成图截图与脱敏SQL/字节散列。仅撤销自己建立的映射，确认自己的服务停止；临时改变的系统设置恢复原值。是否移除测试包/相册合成文件依窗口约定，不自动清手机或其他任务材料。

### 独立native probe阶段

在窗口内仅对 `org.hnuhole.post_media_android.probe` 启动 `org.hnuhole.hnuhole_mobile.MainActivity`，intent明确 `hnuhole-device-driver=true`，`hnuhole-device-phase`依次 `media-write`、`media-read`、`media-purge`。每个阶段间只force-stop本probe再启动，确保新进程；不得force-stop主App/其他包。`run-as`只读这个包的 `no_backup/post-media-probe-result.json`与 `files/owned-device-driver-stage.json`，私有VM URI不导出。

- write：实际 `PostStore.openNative`→原生业务vault/Keystore/no_backup路径，9原文件、含多chunk写入，关闭连接，SQL/sidecar无原图头。
- read：强制有同一run成功write见证且writePid不同；9原字节散列一致、错误digest与另一账号读取拒绝、无原图头。原始加密格式/原生插件实现不替换。
- purge：必须先有成功read见证，只清probe自己两个scope；核DB删除、关闭后vault访问拒绝、scope不能重开。没有读取Keystore内部证明key物理删除，不能将访问拒绝泛称硬件密钥擦除证据。

每次核当前`pidof`与stage、report的PID/phase一致，旧PASS见证不得代替新阶段。任何阶段FAIL只给脱敏stage；不要自动重放write或清现有数据。准备时只构建了此probe，三个阶段当时全部NOT_RUN；本轮实际三阶段PASS见上述机器记录。

### 实际业务病例与证据

| ID | 手机窗口执行内容 | 必需证据／准备时状态（当前见本轮报告） |
|---|---|---|
| PMA01 | 本包首次启动、专用C/V、真实原生端口 | 机型/API/ABI、APK/签名、就绪与入口；NOT_RUN |
| PMA02 | probe write→新进程read→purge | 三个脱敏witness、不同PID/9原图/账号隔离/关闭；NOT_RUN |
| PMA03 | 原生Photo Picker取消和选择，仅9张合成图 | 取消不改草稿；实际授权模式/系统界面；不把取消写成权限拒绝；无权限弹窗按实际记N/A；NOT_RUN |
| PMA04 | 九图、排序/移除/替换、仅图发帖与第十张限制 | 图片顺序/ID/摘要，原JPEG/PNG/GIF/WebP无重编码；NOT_RUN |
| PMA05 | 原图草稿、杀本主App后恢复、选图中断 | 原生密钥/SQLite恢复、同账号原图字节；不把原生lost-data挂给后登录账号；NOT_RUN |
| PMA06 | 实际C/V/SQL上传/发布/受保护读取 | 原文件、客户端清单、SQL、读取长度/SHA九份逐项一致，缺项不公开；NOT_RUN |
| PMA07 | 丢CREATE响应、重启核原命令、部分补传/丢PUT收据 | 真实TLS代理计数、只有一次CREATE，成功项不重传，手动只补缺项；NOT_RUN |
| PMA08 | 明确失败后编辑RETRY | 用正式短限制触发，旧暂停状态不污染新版本，原身份/通道固定；NOT_RUN |
| PMA09 | 通道/我的→详情→查看器与返回恢复 | 长图顶部适宽、缩放/旋转/多指、同手势回顶不退出、松手新下拉退出，位置恢复；NOT_RUN |
| PMA10 | 主App原格式保存、连点、保存中关页、临时文件消失 | 真实Gal结果/按钮/反馈/临时文件结算、原字节不变；NOT_RUN |
| PMA11 | 保存后GIF/有限与无限WebP实际回放 | 原文件SHA/loop/帧时长与相册版本分别记录。厂商播放器异常不转算文件损坏，不转换GIF/降质来制造通过；NOT_RUN |
| PMA12 | 删帖/取消/退出/切账号、迟到读取和60秒失效 | 实际C404/SQL清理、未泄露图片、无迟到UI/保存回调；NOT_RUN |
| PMA13 | 新选图/上传控件与实际中文IME/布局 | 新业务控件焦点/状态/溢出；复用旧组件已完成TalkBack，避免全套重测；NOT_RUN |
| PMA14 | 本组合的内存/缓存/临时文件观察 | 仅本包数据；约1MiB九图不能证明九张10MiB最大预算，完整资源预算仍独立；NOT_RUN |

故障注入沿用真实联合runner：`lab.py control --input <Linux本任务private JSON>`，JSON `{ "action": "/fault", "body": { ... } }`。先dropCreate并holdQuery，SQL只读核原受理后，按该task的真实mediaId arm `dropBefore/dropAfter`再放开query，避免未知写入被重发。`/stats`只导计数；`/snapshot`需本任务taskId；`/mute`由已有受标记保护operator调用正式方法，不直接改状态。`/read-hold`在退出前持有真实已授权响应再释放，核迟到隔离。不要给手机、组件或公开日志传控制token或账号秘密。

Android业务验收完成后再更新真实设备结果；iOS原资源适配、已有文字库存量升级、最大资源/生产存储配额与正式部署、评论/私信仍独立。主机10个原图检查与native编译均不能登记为上述设备病例PASS。
