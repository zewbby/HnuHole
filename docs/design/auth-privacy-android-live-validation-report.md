# Android 真机连接实际 C/V 记录

日期：2026-10-05。分支 `codex/auth-privacy-handoff`，基线 `0eff47a21cd4f4ab1636b4468f7d5df9769a264f`，本轮源码未提交。任务单见[真机联调计划](auth-privacy-android-live-plan.md)，逐项结果及源码摘要见[机器记录](../../services/api/authlab/android-live-verification.json)。

## 当前结果

当前 vivo S18 上实际 App→HTTPS 实际 C/V→一次性 SQL／原生 Keystore 的限定基础链为`PASS`。型号 V2323A、Android 15、ARM64；write/read分别为独立进程20708／21981，read核对前一进程ID并恢复同一账号、会话和身份。两阶段均由只连接已安装包的runner执行，阶段间没有安装或卸载。AC05整项、完整设备矩阵、B02整模块与生产仍为`BLOCKED`。

一次性开发数据库、实际 C/V cmd、C迁移12／V迁移4、受限角色、两侧独立开发 Gate 和 Mailpit 均启动成功，两侧 HTTPS readiness 在正常 CA／主机名验证下返回200。服务端应用源码未改变；Docker项目冲突负向检查通过：新建本轮归属标记目录产生同名项目时，在注册清理trap前拒绝执行，原有三个开发容器保持运行；正常启动记录和当前负向保护分别登记。

最终完整 ARM64 测试 APK 构建通过；Flutter analyze 和182项移动端测试通过。Gradle分发包摘要与AC05保留的官方摘要一致，本轮没有重新查询外部校验文件。最终r4 APK SHA256为`b14b71af909ca328178326b76b10bd4151f066aa63e816b590e1fd8da660dbd1`；安装命令返回Success，用户确认安装，runner独立核对手机base.apk摘要一致后才运行。

write完成测试SMTP收码、注册、恢复码完整确认、目录访问和身份创建／改名。read在外部强制结束并重启进程后恢复原生持久状态，读取实际SQL中的改名身份，进入设备管理并退出，等待登出待办完成，确认旧令牌得到未授权响应，再通过现有“前往登录”入口用密码登录、取得新会话并保留同一身份。两阶段均断言普通系统信任拒绝私有CA。最终只读SQL计数包含此前失败尝试：4个合成账号／活动身份／创建回执，3个改名身份／回执，1个活动会话、4个撤销会话和4个保留资格。单次r4的接口断言核对其自己的1个身份，不能把总计数当作一次测试的账号数量。

第一次旧包已实际运行：普通信任拒绝私有CA的TLS断言通过，App完成测试SMTP收码、注册恢复码完整确认、注册、目录加载和身份创建；随后测试夹具过早匹配编辑框文本，查找身份ListTile时出现`Bad state: No element`，整个write阶段记`FAIL`。脱敏SQL读回为1个合成账号、1个活动身份、1个创建回执，0个改名／撤销回执。没有跨进程PASS记录。

修正身份ListTile等待后，r2 write（PID28707）通过，read（PID31758）在返回设置页的动画完成前寻找设备菜单而失败。r3 write（PID12065）通过，read（PID12458）已经完成原生恢复和实际服务端退出，但夹具错误期待自动跳到登录页而超时。最终r4修正为遵循真实页面路由、等待按钮可操作和显式点击“前往登录”，并严格核对旧会话未授权；分析、182项测试、APK和完整两阶段均通过。三次失败保留为`FAIL`，不改写为成功。系统Passkey、iOS、全部设备矩阵、备份／卸载恢复、七天后正式关闭和生产验收均不在本轮已通过范围。

用户已经安装旧包后，默认Flutter drive仍尝试再次安装，是执行入口选择错误；已停止本轮对应进程并确认旧App保留。runner改为`--use-existing-app`，先核验已安装APK摘要与本轮构建一致，再只重启并连接；实际旧包不匹配拒绝保护通过。曾尝试用Flutter attach加载修正Dart代码以免换包：一次端口解释错误，随后暂停启动导致加载超时；没有取得可接受的测试阶段，该实验helper已删除。随后必要的夹具更新经用户授权覆盖安装；最终r4安装成功，两阶段均不安装／卸载。

## 源码与可重复入口

| 入口 | 实际作用与范围 |
| --- | --- |
| [App transport](../../apps/mobile/lib/src/development/app_transport.dart)／[main](../../apps/mobile/lib/main.dart) | `AUTH_DEV_CA_BASE64`只允许debug和独立loopback HTTPS端点；保留链和主机名校验，不安装系统CA、不使用badCertificateCallback；正常配置保留默认信任 |
| [负向测试](../../apps/mobile/test/development/app_transport_test.dart) | 禁止非HTTPS／非loopback／同源／额外路径等配置，错误证书失败，未配置开发CA保留普通客户端 |
| [服务启动器](../../tools/run-auth-device-services.sh) | 自己创建的compose项目、正式迁移／受限角色、实际cmd和开发Gate；无外部DSN参数，退出时只删除本项目数据库和私钥 |
| [真机入口](../../apps/mobile/integration_test/auth_live_device_test.dart)／[driver](../../apps/mobile/test_driver/auth_live_device_driver.dart) | 运行实际main／路由／HTTP／原生vault，测试SMTP收码、恢复码完整确认、身份创建改名、外部重启恢复和旧会话撤销；无AuthApi／IdentityApi替身 |
| [Windows设备runner](../../tools/run-android-live-device.ps1) | 核验已安装包摘要和本轮归属标记；仅启动／连接同一包的两个进程，不安装／卸载；只清自己创建的USB转发 |

| 受影响模块 | 当前证据与待验边界 |
| --- | --- |
| A00 | 当前分析182项／APK构建／runner语法及APK摘要拒绝／Docker项目冲突负向检查、两阶段设备执行PASS；交接核验另列 |
| A01／A11 | 实际C/V启动、正式迁移、受限角色和TLS readiness、main／transport改动后的真实App受保护目录及私有CA负向断言PASS；完整设备Gate矩阵未验 |
| A05／A12／A13 | 当前SMTP注册、恢复码完整确认、会话／目录、退出、旧令牌未授权及再次密码登录PASS；完整恢复／注销／故障矩阵未验 |
| N01／B01 | 当前真实FlutterAuthVault／Keystore跨进程恢复和实际设备管理退出PASS；锁屏、卸载、备份、跨设备及其他管理操作未验 |
| B02 | 当前实际身份创建／改名、跨进程恢复和再次登录保留身份PASS；七天正式关闭设备链和全部身份故障矩阵未验，业务联动仍待后续实现 |

相关X01／X02／X03／X04／X08只按实际注册、会话、存储和身份子场景映射，完整跨模块故障矩阵未通过。上述真实源码是main、transport、现有auth／identity控制器、原生vault；本轮新增测试文件与入口见前表，各模块台账`currentAndroidLiveRegression`单独登记。

服务端源码和Gate文件在WSL Linux文件系统运行。先准备明确归属的私有工作目录，写入`OWNER`内容`HNUHOLE_ANDROID_LIVE_DEV_V1`，设置`AUTH_DEVICE_WORK`，加载已有[WSL环境](../../tools/env-hnuhole-wsl.sh)，执行`sh tools/run-auth-device-services.sh`。依赖下载按当次授权；脚本只使用现成工具和缓存镜像。服务就绪后工作目录生成`device-config.json`，含loopback端点和公开CA，不含私钥／数据库密码。

移动端加载已有Flutter／JDK／SDK，使用专用pub／Gradle缓存，在Linux源码工作目录执行：

```sh
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --target-platform android-arm64 --target integration_test/auth_live_device_test.dart --dart-define-from-file=/absolute/owned/work/device-config.json
```

把APK、公开配置和同版本移动端／包源码放入明确归属的Windows驱动目录，取得驱动Dart依赖。先确认测试App是本轮新安装、没有占用已有用户App；手机解锁并允许一次安装／覆盖更新。安装在runner之外显式执行：

```powershell
adb -s '<已授权设备ID>' install --no-streaming -r '<本轮APK绝对路径>'
```

仅在确认安装来源和本轮归属后，在驱动目录写入`.device-app-owner`，内容为`<设备ID>|<device-config.json中的AUTH_DEVICE_RUN_ID>`，不附换行。它是私有运行标记，不提交设备ID。随后执行：

```powershell
& .\tools\run-android-live-device.ps1 -DeviceId '<已授权设备ID>' -Apk '<本轮APK绝对路径>' -ConfigFile '<本轮device-config.json>' -DriverWorkspace '<同版本apps/mobile目录>' -PubCache '<专用pub缓存>'
```

本轮必要缓存重建已获用户授权。运行需手机解锁、USB调试授权及系统允许安装测试App；手机返回拒绝时停止并请用户处理，不绕过安装确认。设备截图／测试报告不保存密码、OTP、恢复码或会话令牌。报告仅保留阶段、PID和布尔断言。

## 历史证据与后续步骤

AC04／AC05／AC06原记录保持原摘要。旧AC06入口和台账用已发布72ca9e8的Git字节复核；当前记录另立新源码摘要，不能拿历史PASS代证本轮main的连接配置。受影响A00／A01／A11／A05／A12／A13／N01／B01／B02当前验收重新打开。B02业务联动未实现部分保持原状态，生产分权和独立审计继续单列。服务端完整Go／SQL／race／vet、R03／R05没有本轮重跑，保留AC04精确历史证明范围。

当前临时资源已清理、本地交接检查通过。下一步按平台任务单补系统Passkey的RP／Android签名关联部署、macOS／Xcode／iOS，以及剩余设备故障与Gate／注销场景。各项分别记录环境、入口和真实结果，不扩展完整业务模块。

本轮清理PASS：删除已确认归属的WSL一次性C/V／Gate watcher／Docker容器、卷和网络、私钥及专用Go/pub/Gradle缓存；删除Windows专用driver/pub缓存、配置、APK及原始日志，停止本轮下载桥接和9个父进程已结束的Flutter日志采集子进程。Windows目录曾被这些logcat进程占用，核对确切命令、日期与PID后仅停止本轮残留，随后目录删除成功。手机临时测试App原先不存在，本轮按包摘要及归属标记核对后卸载；手机临时push APK已不存在，无未知文件删除。最终验证两侧专用目录、Docker项目和测试包均不存在，USB forward/reverse为空。现成SDK／AVD／Flutter／JDK、用户数据、其他Docker项目和预先存在的Android调试密钥保留。测试源码和小型脱敏记录保留。未提交／推送／部署。
