# 第一项单台 Android 验收：非手机准备完成

2026-10-15，Asia/Shanghai。结果 **PASS_NON_PHONE_PREPARATION_DEVICE_NOT_RUN**。用户要求先完成第一项除手机配合外所有工作；本轮没有连接或使用手机、没有调用 ADB。CA-A01–A07/A10 的设备结果仍为 NOT_RUN，任务2–4、iOS和生产分别待验。

起始 HEAD `01ea1a13b89aac8bf76e5ab7eb20eca4fb2662ee`；原整合产品 `28cee4656edd710d60676a81794c20cd49f45351`，固定认证 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。执行时使用本任务未提交源码，450项规范化输入 SHA256 `713098a87c032c404ac182d6091e3d73a916aa880770de77c3700c9e6dc483ae`。发布固定 SHA 见 Git 回执，正常推送本分支，不合 main 或发布。

## 修复与范围

1. DELETE 成功回包丢失且首次原结果 GET 失败时，命令已落盘却没有进入 controller 的 poll 集合。新增用例先复现 FAIL；发送前刷新本账号本地集合并保留 authority 检查，正常五秒 poller 只查询原命令，不再次 DELETE。账号切换、迟到响应、持久 DELETED 和重开围栏在全量回归中通过。
2. C 正常密码登录取消注销后，回执保留而 UI 缺少完成入口，会阻止新注册或另一账号注销。仅 C 已核对为 CANCELLED 时显示“结束已取消的注销操作”，调用现有 forgetClosureStatus 守卫。PENDING/UNKNOWN 不可结束，不自动登录；认证协议、AuthFlows、session/HTTP、native、manifest、SQL/授权和锁均未改。

未重新开发 F1–F3 或新增业务。新增真实 cmd/TLS/SQL 故障代理、共享 host/device 场景和带确认门槛的 Windows 现场启动器，见[工具说明](../../tools/community-android-stage1/README.md)。Host 使用文件 vault/key 和幂等文件关闭清理替代端口；Android 调用实际 app.main 与原生依赖。Host 结果不记为设备通过。

## 实际执行与最终覆盖

| 检查 | 本轮最终结果 |
|---|---|
| checks | analyze 0；mobile322 PASS、0 FAIL，含两个新增缺陷回归 |
| auth-regression | 原 R05 真实 Dart→TLS C/V→SQL PASS |
| integration | 原 F4-H01–H08 八项 PASS |
| server | 六 Go 测试包真实 SQL/race 与内置 vet PASS；authprivacy1174.263秒，未关闭 fsync 或放宽断言 |
| posts-privileges | 九顶层/四生命周期 PASS，真实受限 runtime 和负权限 PASS |
| auth-runtime | 实际 cmd/mTLS/signed Gate、正式 Goose C13/V4 及 R03 25断言 PASS |
| vet | 最终 go vet PASS |
| 新整段主机排练 | 新空库 lab21，HOST-CA 八检查点 PASS；CREATE2/RETRY1/DELETE1、唯一键2/1/1、成功回包丢弃3次 |
| 工具守卫 | Linux125 PASS；Windows现场工具9 PASS，含合成 VM 传输；没有 ADB 调用 |
| 构建 | 最终隔离 acceptance/normal Debug ARM64 同新签名 PASS；标准 main unsigned Release ARM64 PASS，未安装/发布 |

七阶段顺序实际执行一次；最后 auth_screen 产品修改后 checks/R05/F4 重跑。Go/SQL/native/锁字节未改变，对应新 server/权限/runtime/vet 覆盖这些最终字节。后续仅修订新增场景等待和主机替代端口，最终 analyze、lab21 整段排练和 acceptance APK 分别覆盖末次修订。历史320、旧311/308或认证22/0/2不计本轮。

日志根 `E:/HnuHole-community-f4-20261012/stage1-preparation-20261014/logs`。最终三项在 final-mobile-regression，其余在 final-regression；新排练为 host-stage1.jsonl，构建为 acceptance-final-build.log、normal-final-build.log 和 standard-release-build.log。时间、退出码、SHA、SQL计数和制品信息见[机器记录](community-android-stage1-preparation-20261015.json)。

实际入口是 `wsl -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/<wrapper>.sh`；wrapper 为 run-final-regression.sh、run-final-mobile-regression.sh、run-host-stage1.sh、rebuild-final-apks.sh、rerun-standard-release.sh、verify-final-artifacts.sh、run-tools-final.sh。根入口为 `bash tools/run-community-flutter-f4-linux.sh <stage>`；新场景为 `flutter test --no-pub --machine --dart-define-from-file=<owned私有配置> integration/community_stage1_host_test.dart`，配置内容不公开。

修复前两项 FAIL、旧场景失败、首次错误 no-pub Release、fixture teardown 竞态均保留脱敏记录。Teardown 改为等待真实第二账号 scope 激活；Release 使用交接明确的正常入口重新生成注册表，锁未变。场景补齐 OTP202 原结果读取、启用控件等待、失败卡片直达重试、异步受理/自动返回时序和幂等 host purge。首次固定制品下载超时正常重试；专用 SDK 初始化 fetch-tags 超时通过进程级 CI 解决，未升级 SDK 或改代理证书。

## 隔离环境与保留

写入仅在本任务 root `/home/hnuhole/hnuhole-community-flutter-f4-s1-20261014` 和 tool root `/home/hnuhole/community-android-stage1-20261014-tools`，各有匹配 owner。Flutter3.47.5/Dart3.13.4、JDK17、Android build-tools36、Go1.22.2、PG16、Goose 使用既有工具的独占副本/已核对路径。bin/cache、HOME、XDG、Pub/Go/Gradle/tmp、签名和 CA 独立，未调用共享 SDK/ADB，未安装整套工具链或改全局配置。大缓存位于 E 上的 WSL，C 盘保持约18GiB空余。

主机 PG 只用新私有 socket 一次性库；排练和手机分别创建不同 Docker project/九个随机 loopback 端口的新 C/V 库与 Mailpit。正式迁移/最小权限未变。三个 Go 文件 overlay 只注入有界0–8天 Gate/开发 evidence 时钟及 posts 调度暂停；正式七天期限、worker、签名/mTLS和系统时钟不改。推进七天加一秒，不声称自然等待。Proxy 只在真实2xx响应后丢一次回包并阻断原结果 GET，不重放写入或保存原证明、命令键和正文。

旧主机 lab1–21 的数据库卷、进程、私有材料与二进制均按 canonical 路径、owner、进程起始 ticks 和 project 核对后清理。按用户“到时候直接配合”的要求，保留专用 SDK/cache、手机新空库、调试签名/CA 与 APK，全部在 Git 外。手机 fixture 账号0、帖子0、clock0，与排练材料不同；Windows 正常 TLS/Mailpit loopback 可达，未改系统信任。

开窗前由本会话快速复核服务、空库、摘要、证书期限和端口，不要求用户重备环境。当前证书期限见 manifest；电脑重启需恢复本任务服务，证书超期需重建本任务材料。

## 到时配合与未验

确认一台实体 ARM64 Android 的型号/ID、约30–45分钟窗口、认证会话已释放；允许本任务独立包安装/更新、新专用 USB 调试 key，手机授权弹窗由用户确认。包名 `org.hnuhole.hnuhole_mobile.communityf5`，同新调试签名的两 APK；不覆盖认证包或未知同名包，不卸载、清数据、整机重启，不替换既有 reverse 或调用默认 ADB server。启动器要求 window/install/auth-release/own-key 四个显式确认，拒绝默认5037、占用端口与继承的外部 ADB socket/key。

自动流程经实际 main、native vault/SQLite 和真实 C/V/SQL 执行登录、身份、文字页、重试、删除、账号隔离和闭号；再用同签名 normal APK 保留本任务账号 A。最后用户以真实系统输入法输入中文/换行，查看列表、详情、我的和草稿，记录机型/OS/输入法/时段及脱敏事实。自动 enterText 不代证 IME，当前设备、实际插件与 IME 全部 NOT_RUN。

任务2原生7/16/12套件与进程/重启/备份、任务3真实系统 Passkey/独立 RP、任务4双实体 NI-X01/X02 保持待执行。iOS、生产、完整 App/模块和 Release 发布不因本准备通过升级。
