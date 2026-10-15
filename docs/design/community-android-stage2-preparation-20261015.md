# Android任务2非手机准备报告

2026-10-15，Asia/Shanghai。**非手机准备完成；任务2设备验收 NOT_RUN。**任务1与任务2可顺序进行。本轮只新增验收测试/工具/脱敏交接，没有改动已完成页面或产品协议，没有调用 ADB、使用手机、创建真实账号凭据或更改系统设置。

起始 `d686d6582d74de1d0b578815d879be33d14b5695`，分支 `codex/community-flutter-pages`，origin 已核对为 zewbby/HnuHole，开工时工作区干净、远端同 SHA。产品源码仍为 `b5accf36b90e27829b6d039cd58a5b9c189a3da8`；认证固定来源 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。完整运行输入见[本轮指纹](community-android-stage2-source-fingerprint-20261015.json)，逐项确认 task1 的全部 450 项输入未变，新增 6 项测试/工具输入。Git 保存提交及远端回执在[交付记录](community-android-stage2-delivery-20261015.json)补记；不合 main，不发布或部署。

## 完成内容与隔离

- 新增 `apps/mobile/integration_test/community_android_storage_test.dart`：实际 vault 插件及 `PostStore.openNative`/打包 SQLite 的分阶段 write/read/reboot-read/purge/closed。A/B 合成草稿、原 commandId/digest/identity/channel、认证独立 namespace，以及跨进程墓碑、key/file 清理和 B 保留均有断言。它不启动 main、不调用 HTTP、不创建可用认证会话；只验证本地 adapter，不能代证权威 CLOSED 或实际账号登录恢复。
- 新增 `tools/community-android-stage2/phone.py`：精确选择 business7、vault16、codec9+errors3，共35项；另准备原认证3组真实进程中断 probe。独立安装/强停包 allowlist、完整成功和准确计数、跳过拒绝、阶段 latch、同机/PID/boot ID、固定 APK 与 server 身份均有守卫。UNKNOWN/失败不能自动重放；不含卸载、清数据、整机 reboot 或系统设置命令。
- 新增 build/import/verify 工具和11项聚焦主机守卫。只读复制约4.5MB既有公开 Maven blobs 到本任务本地 repository，保持原始 POM/module/版本与内容哈希，未复制 cache metadata 数据库或锁。镜像 overlay 仅为 app applicationId、两个 testNamespace/testApplicationId，以及本地公开 Maven repository。
- 构建并核对3个 Debug APK：产品测试包 `org.hnuhole.hnuhole_mobile.communityf5.storage`，两个 instrumentation 包 `org.hnuhole.communityf5.storage.vault.test` / `org.hnuhole.communityf5.storage.passkey.test`。它们使用本轮独立新调试签名，与 task1 签名不同；两原生包均 self-target、匹配 AndroidJUnitRunner。DEX 包含所选测试类；源码实际计数7/16/9/3。实际设备计数仍 NOT_RUN。
- 核对199项构建镜像输入、产品 noBackup 路径、编译后的 allowBackup/fullBackupContent=false 与 cloud/transfer 各9个排除域、ARM64 SQLite raw 固定哈希和 Gradle strip 后 APK 文件的一致性。未借用认证 RP、签名、账号或密钥。备份配置/源码检查不代证真实 OEM 搬家。

本轮目录 `E:/HnuHole-community-f4-20261012/stage2-preparation-20261015`，WSL root `/home/hnuhole/community-android-stage2-20261015`，均有 owner。SDK 为 task1 已有独占副本 `/home/hnuhole/community-android-stage1-20261014-tools`；执行前确认没有并行 Gradle 构建，顺序复用**当前社区任务自己的** SDK/pub/Gradle cache，SDK bin/cache 写入仍在该独占副本。task2 HOME、调试 key、源镜像、temp、日志和 ADB home 独立。未操作原共用 SDK/认证环境/全局配置；未安装工具链；本轮不创建或连接新业务数据库。

## 实际执行与最终代码覆盖

完整命令及手机 SOP 见 [tools README](../../tools/community-android-stage2/README.md)。下表日志根为 `E:/HnuHole-community-f4-20261012/stage2-preparation-20261015/logs`；WSL 日志已另复制到 `logs/wsl`，原路径 `/home/hnuhole/community-android-stage2-20261015/logs`。

| 实际命令/阶段 | 本轮结果 | 日志与覆盖 |
|---|---|---|
| `flutter pub get --offline --enforce-lockfile` | PASS，锁未变 | wsl/pub.log；最终新 Dart 测试及原产品输入 |
| `dart format integration_test/community_android_storage_test.dart`；`flutter analyze --no-pub` | PASS，0 issues | wsl/format.log、wsl/analyze.log；最终 Dart |
| `flutter test --no-pub --machine test` | PASS，322项，0失败/跳过 | wsl/mobile-tests.jsonl；最终产品输入及原 host suite，**不是新增原生设备测试执行** |
| `flutter build apk --debug --no-pub --target-platform android-arm64 --target integration_test/community_android_storage_test.dart --dart-define-from-file=<owned build-config.json>` | PASS，最终配置重建 | wsl/final-app-build.log；与核对过的最终镜像一致 |
| `./gradlew --offline --no-daemon --max-workers=2 :hnuhole_auth_vault:assembleDebugAndroidTest :hnuhole_auth_passkey:assembleDebugAndroidTest` | PASS | wsl/instrumentation-build.log；7/16/12及中断 probe 只编译，不计设备PASS |
| Windows / Linux `python -B -m unittest discover -s tools/tests -p 'test_*.py' -v` | Linux136 PASS；Windows133 PASS＋3 SKIP；本轮新增11项均PASS | linux-host-tests.log / windows-host-tests.log；最终 Python，包含 server 归属、逐项授权、未知结果、重启确认、原生选择/计数及公开依赖完整性 |
| `bash verify-artifacts.sh` → repo `verify.py` | PASS | device-window/artifact-proof.json；199镜像输入/3签名/manifest/DEX/SQLite，最终6项新增输入指纹 |
| Windows `load_manifest`＋端口 bind、前后 SHA；只读 task1 `/health/ready` 与 stats | PASS | device-window/host-preflight.json、stage1-preservation.json、stage1-lab-preservation.json；无ADB |
| `python -B tools/community-android-stage2/phone.py --plan-only`；`bash -n tools/community-android-stage2/build.sh` | PASS | 无设备动作；规划入口/脚本语法 |

Windows的3个SKIP仅为现有 task1 POSIX权限/owner/symlink测试，在本轮Linux已实际通过。当前无未解决 FAIL。最初新增 Dart 的 const/nullability 提示已修正并重跑分析；最初 native 离线缺少固定 AndroidX 测试依赖，经最小公开依赖复制解决，最终 app 与两个 native 包均重新构建成功。AGP/Kotlin弃用和现有SDK XML版本提示仍为构建警告，本轮没有通过升级来隐藏它们。

本轮没有修改 main/settings、AuthFlows、session/HTTP、closure、原生产品 vault/passkey、manifest、SQL、授权或锁。故 task1 的 mobile/R05/F4/server/posts-privileges/auth-runtime/vet 等证据保留其原日期/版本，可用于**未变产品输入**；未把它们改记为本轮新执行。本轮新执行的主机测试/分析/构建覆盖最终新增测试与工具，不能外推为设备或系统 Passkey通过。

## 任务1保留核对

前后 task1 manifest、proof、acceptance.apk、normal.apk、标准未签名 Release、公开 CA、endpoint record 的 SHA256 全相同；450项源码输入也全相同。手机待验 C/V `/health/ready` 各200，合成库账号/帖子仍0，时钟offset=0，publication没有暂停。没有创建 stage1/device-started 或 stage2/device-state，也没有生成任一 USB adbkey。未占用手机或改变任务1的故障控制状态。新原生/存储测试不访问 task1数据库。

开工只读容量 C=19,144,519,680 bytes、E=156,014,907,392 bytes。全部大型制品、缓存和临时文件留在E盘/其WSL；没有恢复C盘大型缓存。按用户“到时直接配合”要求保留两项专用待验材料，暂不执行原AGENTS的任务资源清理；只保留小型脱敏源码/记录到Git，调试私钥/APK/缓存/数据库及原始日志不提交。

## 手机窗口中的剩余工作

1. 确认具体实体设备、时段、认证会话释放和三个独立新包/USB key/仅自身强停授权；执行 `suites`（7+16+12及3组原认证中断），再 `write → read`。从实际输出记35项，核不同原生PID，任何失败/UNKNOWN先停。
2. **另获整机重启许可**后由用户重启/解锁，执行 `reboot-read`，核 boot ID 确实变化；无许可则 CA-A09 保留NOT_RUN。然后 `purge → closed`，在新进程核A墓碑/文件消失、B及认证记录保留。不能用这些合成 fixture 证明服务端 CLOSED。
3. 使用任务1正常App和其正常创建的合成账号，获仅该包强停/重开授权后验证实际 main、会话/HTTP、中文草稿/原身份通道及适用的原命令恢复。真实中文IME及适用TalkBack由用户配合；不得自动启用读屏/改系统设置。详细逐步操作和事实记录见README。

CA-A08/A09/A11/A12及实际插件/Keystore/跨进程/重启/IME/读屏仍全为NOT_RUN；不存在当前设备失败结果，阻塞是用户尚未提供设备窗口。任务3实际系统Passkey/独立公开RP、任务4双实体NI-X01/NI-X02、iOS、生产与完整App验收继续独立，不计入本轮通过。
