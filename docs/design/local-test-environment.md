# Windows＋WSL 本机认证验证环境

配置日期：2026-10-04（Asia/Shanghai）。远端基线为 `codex/auth-privacy-handoff` 的 `d624ea30943a2b12096c20dbeefd844ba0e5e840`；本次修改的源码摘要见[最新验证记录](../../services/api/authlab/identity-runtime-test-verification.json)。工具安装在用户指定的 `D:\zewbbyTest\Hnuhole-env`，不提交 SDK、缓存、私钥、APK 或数据库。

## 已安装工具

| 工具 | 版本／位置 |
| --- | --- |
| Windows Flutter／Dart | Flutter 3.47.5／Dart 3.13.4，`windows/flutter` |
| WSL Flutter／Dart | 同版本，`linux/flutter` |
| Microsoft JDK | 17.0.20.1+1，`windows/jdk-17.0.20.1+1` 和 `linux/jdk-17.0.20.1+1` |
| Android SDK | `android-sdk`（Windows）和 `linux/android-sdk`（WSL）；API 36、Build Tools 36.0.0、NDK 28.2.13676358 |
| Android Emulator | Windows 37.2.12，Google APIs API 36 x86_64；AVD `hnuhole-auth-api36-test` |
| Gradle | 项目 wrapper 9.3.1；Windows 和 Linux 使用分开的缓存 |
| WSL 已有工具 | Ubuntu-24.04、Go 1.22.2、PostgreSQL 16.15 |
| WSL 生成与迁移工具 | `linux/bin`：sqlc v1.27.0、oapi-codegen v2.4.1、Goose v3.22.1（排除无关数据库驱动） |
| OpenAPI 校验环境 | `linux/python-validation`：openapi-spec-validator 0.9.0、PyYAML 6.0.1；WSL脚本设置 PYTHONPATH |

Windows 的原有 Java 21 保留；本项目通过脚本选择 Java 17。环境变量只作用于当前终端，不写全局 PATH。

## 加载环境

PowerShell 在仓库根目录运行：

```powershell
. .\tools\env-hnuhole-windows.ps1
flutter --version
adb devices
```

仓库外可运行 `. D:\zewbbyTest\Hnuhole-env\env-windows.ps1`。WSL Ubuntu-24.04 的 Bash 终端运行：

```bash
source /mnt/d/zewbbyTest/Hnuhole-env/env-wsl.sh
flutter --version
java -version
go version
psql --version
sqlc version
oapi-codegen --version
```

可用仓库内 `source tools/env-hnuhole-wsl.sh`；脚本支持 `HNUHOLE_ENV_ROOT` 覆盖安装根目录。服务端和 Android 构建的源码 checkout 放 WSL 的 Linux 文件系统。本次一次性 checkout `/var/tmp/hnuhole-auth-validation-20261004` 已在验证结束后清理；复验时重新在 Linux 文件系统拉取对应分支，并核对 Git HEAD 和改动。

当前脚本采用 `pub.flutter-io.cn`、`storage.flutter-io.cn` 和 `goproxy.cn,direct` 下载依赖；如需使用官方源，在 source 后覆盖对应变量。安装的 Flutter、Android 命令行工具及 Gradle 包按官方公布的 SHA-256 验证；JDK 下载自 Microsoft 官方链接，记录的本地摘要不宣称是独立官方校验。

## 已执行验证及证明范围

| 入口 | 结果 | 范围 |
| --- | --- | --- |
| R04 mobile `flutter analyze`／`flutter test` | PASS，175 项测试 | 全部现有 Dart 单元／controller／widget 测试；包括 B02 和共享认证回归 |
| R05 `sh authlab/run-mobile-isolated.sh` | PASS | 真实 Dart→HTTPS→C/V handler→一次性 PostgreSQL，含 B02 丢响应、原键核对、会话变化；vault 为内存替身 |
| R07 标准 Android debug app | PASS | WSL 编译完整 ARM64 app 与两个插件；不代表发布签名或真机运行 |
| R07 Android vault instrumentation | PASS，16 项＋3 组两进程探针 | API 36 模拟器中的真实 Keystore、文件提交与进程中断恢复 |
| R08 Passkey Dart／Android codec | PASS，9／5 项 | 策略、响应校验、取消／归属与原生编解码；不代表系统注册／恢复 ceremony |
| R09 Flutter Android write／read | PASS，两个阶段各 2 个业务测试 | 原生 vault、不同 PID、退出围栏与原凭据结果 key；授权 API 为专用替身 |
| R00 sqlc／oapi-codegen | PASS | 固定工具生成、目录契约本地 baseline 重生成比较；生成物被忽略，不是已提交生成物的 CI 漂移证据 |

R03 的非 owner 实际 C/V HTTPS/mTLS 进程、正式迁移与升级证据保留 2026-10-03 原版本信息。若本次重新执行，另行登记日期与结果；旧通过不自动换绑新源码摘要。

本次修复了两处页面括号遗漏、重复 controller.load、取消围栏测试时序、widget 的 FakeAsync 等待和 Passkey 测试夹具的 Map 值类型。安全管理 widget 测试仍通过真实按钮触发轮换／确认／核对／退出。

## 复验命令

```bash
# WSL checkout/apps/mobile
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --target-platform android-arm64

# WSL checkout/services/api：runner 只用自身建立的一次性库
sh authlab/run-mobile-isolated.sh
sqlc generate
go test ./internal/channels/...
go vet ./internal/channels/...

# WSL checkout 根：生成物是被忽略的本地 baseline
sh packages/openapi/generate-channel.sh
sh packages/openapi/generate-channel.sh --check

# 原生 instrumentation APK，先从 WSL 编译
cd apps/mobile/android
./gradlew --no-daemon :hnuhole_auth_vault:assembleDebugAndroidTest :hnuhole_auth_passkey:assembleDebugAndroidTest
```

PowerShell 加载环境后，可启动已安装的 AVD：

```powershell
Start-Process "$env:ANDROID_HOME\emulator\emulator.exe" -WindowStyle Hidden `
  -ArgumentList '-avd','hnuhole-auth-api36-test','-no-window','-no-audio','-no-snapshot','-gpu','swiftshader','-memory','2048'
adb devices
# 用实际设备 ID 替换 emulator-5554；必须等 sys.boot_completed 返回 1
adb -s emulator-5554 shell getprop sys.boot_completed
```

将编译出的 test APK 复制到 Windows 可访问路径，然后在仓库根运行：

```powershell
& .\tools\run-android-vault-probes.ps1 -DeviceId emulator-5554 -TestApk '<vault test APK 绝对路径>'
adb -s emulator-5554 install -r '<passkey test APK 绝对路径>'
adb -s emulator-5554 shell am instrument -w -e class org.hnuhole.authpasskey.PasskeyCodecTest org.hnuhole.authpasskey.test/androidx.test.runner.AndroidJUnitRunner
```

真实 Flutter 两进程探针先在 WSL 为两个阶段编译，使用同一唯一 namespace 和相同 debug 签名，中途不能卸载或清数据：

```bash
# apps/mobile；分别把两个 APK 复制到 Windows 可见的 write.apk/read.apk
flutter build apk --debug --target-platform android-x64 --target integration_test/auth_security_device_test.dart --dart-define=AUTH_DEVICE_PHASE=write --dart-define=AUTH_DEVICE_NAMESPACE=native.security.test.unique_run_01
# 复制 write APK 后再构建 read；同一 namespace
flutter build apk --debug --target-platform android-x64 --target integration_test/auth_security_device_test.dart --dart-define=AUTH_DEVICE_PHASE=read --dart-define=AUTH_DEVICE_NAMESPACE=native.security.test.unique_run_01
```

```powershell
& .\tools\run-android-auth-process-test.ps1 -DeviceId emulator-5554 -WriteApk '<write APK 绝对路径>' -ReadApk '<read APK 绝对路径>'
```

该脚本使用 `flutter drive --keep-app-running` 后显式 force-stop。Flutter 3.47.5 的默认 drive 清理会卸载 app，导致第二阶段数据消失；首次失败和修复后的通过记录均保留。

## 环境限制与未完成项

本机 Windows Gradle 在执行项目之前失败于 `Unable to establish loopback connection`／Windows UnixDomainSockets `Invalid argument: connect`，Java 17 和 IPv4 参数没有解决。WSL Gradle 构建已通过；Windows Flutter 分析／测试／预编译 APK 的 drive 可以运行。

iOS 完整 app／Keychain／系统 Passkey 需 macOS 和完整 Xcode。真实 Passkey ceremony 仍缺 RP 域名、Android 发布签名、iOS Team／关联部署。API 36 模拟器通过不覆盖物理设备硬件安全等级、锁屏、OEM、完整备份与平台矩阵。B02 输入法／无障碍设备矩阵和身份专属草稿跨进程场景未验；当前两进程 Flutter 探针覆盖共享认证状态。

AC01 V 独立 Gate、AC02 现有身份整账号关闭联动及后续业务投影仍未实现；P02–P06 的生产／独立审计证据仍缺。B02 整模块继续 BLOCKED。最新状态以[模块台账](module-acceptance-ledger.json)和[验证报告](identity-management-validation-report.md)为准。

按用户最终选择，SDK、JDK、固定工具与 AVD 配置留在 D 盘；下载包、pub／Gradle／Go／pip 缓存、APK、大日志、AVD 测试运行磁盘／快照、临时库／测试私钥和一次性 checkout 均已清理。D 盘实测空闲空间增加约 12.54 GiB；WSL 清除 checkout／Go 构建缓存并执行 TRIM，TRIM 的总块数不计为本次释放量。首次复验需要重新获取依赖和 Gradle wrapper，AVD 会重建干净运行磁盘。不做 Docker 全局 prune，保留原有镜像。
