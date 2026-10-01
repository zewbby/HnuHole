# 移动端原生存储与真实 C/V 联调交付记录

日期：2026-10-01。仅基于 `codex/auth-privacy-handoff`；上一切片为 `95bb54ecade2b547129df71fe2675e54384fcfed`。机器证据见 [mobile-native-integration-verification.json](../../services/api/authlab/mobile-native-integration-verification.json)。历史验证记录保持不改。

本轮完成真实 Dart 客户端到隔离 C/V HTTPS 与两个独立 PostgreSQL 库的认证联调，修复原生存储边界并加入 Android 设备故障测试。本机只完成 Android 原生／测试编译与测试 APK 组装，以及 macOS 安装标记回归；设备执行、完整应用构建和 iOS Keychain 验证交给另一台电脑继续。用户要求收尾清理大型验证文件并推送远端，本轮不启动模拟器。

## 真实认证联调

`authlab/run-mobile-isolated.sh` 创建临时 PostgreSQL 集群，使用私有 Unix socket、分离的 C/V 数据库和非超级用户。退出时停止集群并删除数据。Go 测试启动真实公共 HTTPS 处理器和内部 mTLS 对端，再调用真实 Flutter 测试与产品 `HttpAuthApi`／认证状态机。

验证了校邮申请响应丢失后沿原键核对、持钥注册、恢复码确认、单设备接替、权威会话恢复与续期、未知退出结果及客户端重建后补撤销、Gate 冻结返回 503 且保留令牌、受限签名恢复推进 generation 后旧令牌返回 401、未知重设结果沿原键核对、未知注销结果核对、截止前主动登录取消，以及可信时钟到期关闭和 C/V 释放收据 ACK。

故障发生在真实处理器提交完成后丢失响应；冻结、恢复、截止和收据使用真实领域服务，不直接改 SQL 结果。测试 CA 和随机能力保护的故障控制入口仅存在于测试代码。Dart TLS 保留证书链和主机名校验；没有 `badCertificateCallback` 或生产 TLS 绕过。Dart 与现有 Ed25519 TLS 测试证书不兼容，因此新增公共测试链使用 ECDSA P-256，授权协议的 Ed25519 和内部 mTLS 不变。

客户端存储端口采用测试内存记录并重建控制器，证明持久工作流的序列化／重新读取契约，不能证明原生落盘或断电恢复。业务目录明确返回测试 503；尚未证明“真实客户端→C/V→生产目录”整链。

## 原生存储修复与测试

- Android：将真实 Keystore／AES-GCM／AtomicFile 核心提取为内部实现，故障 seam 仅替换文件提交边界，不替换加密。用公开的 `Os.fstat`／`S_ISDIR`／`fsync` 取代 Android SDK 未导出的 `O_DIRECTORY`；跨 engine 在进程内串行。写入前验证旧记录，损坏、超限或缺密钥时拒绝覆盖；有界读取也防止 stat 后增长造成无界分配。空字符串与最大 UTF-8 长度有明确边界。
- Android：加入 16 项 instrumentation 测试，覆盖真实 Keystore、随机 IV、namespace AAD、备份隔离、损坏／丢密钥／超限、同步与替换失败、未知确认及旧／新完整状态恢复；另有外部驱动的跨进程中断探针。本轮这些测试已编译，**未在设备上执行**。
- iOS：安装标记已写入但同步失败时，旧代码下一次见到标记就直接访问 Keychain。现在每次访问都重新确认标记和目录同步，失败仍拒绝授权状态访问。标记读取有界，损坏标记拒绝而不删除 Keychain。macOS 真实文件系统回归先复现失败，再验证修复，覆盖重试、目录同步、损坏和重新安装。
- iOS：实例级队列允许多个 Flutter engine 首次安装检查与 Keychain 删除交错，可能删除刚确认的新状态；改为进程共享串行队列，覆盖标记检查及全部 Keychain 操作。此项依据代码交错分析修复，本轮只有 Swift 语法核对，没有 iOS 多 engine／Keychain 实测。

Android 原生生产代码与 instrumentation Kotlin 编译成功，测试 APK 组装成功；APK 约 3.2 MiB，SHA-256 为 `ccac66036873593a45da071a94a0a6fe8c9e4351c968a91108334cec7cef2d97`，实际 manifest 的 package／targetPackage 均为 `org.hnuhole.authvault.test`。APK 是测试库宿主，**不是完整移动应用**，收尾按用户要求删除。

本机缺 NDK 28.2.13676358。显式 `-I prebuilt-debug.init.gradle` 只移除 Flutter SDK 的纯注释空 CMake 配置并保留预编译库调试符号；真实 CMake／ndkBuild、native hooks、新 Android plugin、release／profile 均拒绝。默认构建策略不改；不能用该调试入口代表标准 release 构建验收。完整 Xcode 和 iOS 设备不可用。

## 另一台电脑复验

本轮收尾实际结果：

| 检查 | 结果 |
| --- | --- |
| `sh authlab/run-isolated.sh` | 退出 0；真实隔离 PostgreSQL race 回归与 vet；authprivacy 100.431 秒，HTTPS 包 8.478 秒 |
| `go test -race -count=1 -p 1 ./...` | 退出 0；直接运行无 C/V DSN，SQL 证据来自上项 |
| `go vet ./...` | 退出 0 |
| `sh authlab/run-mobile-isolated.sh` | 退出 0；一条完整 Dart 认证链与真实 HTTPS／SQL，Go race 包 8.920 秒 |
| `flutter analyze --no-pub` | 退出 0，无问题 |
| `flutter test --no-pub --reporter expanded` | 退出 0，78 项通过 |
| Android `compileDebugAndroidTestKotlin`／`assembleDebugAndroidTest` | 均退出 0；13／21 秒；未运行设备测试 |
| macOS 安装标记 runner | 退出 0；标记重试／目录同步／损坏／重装回归通过 |
| Swift parse／podspec Ruby syntax／`git diff --check` | 均退出 0；Swift parse 不等于平台链接 |

早先并行验证遇到本机磁盘耗尽，失败运行不计为通过；清理本轮可再生下载／构建缓存后，改为串行执行以上收尾检查。

先拉取指定分支，准备 Flutter、Go、PostgreSQL 工具；`go`、`initdb`、`pg_ctl`、`psql` 要在 PATH 中。先在 `apps/mobile` 运行 `flutter pub get`，再执行：

```sh
# apps/mobile
flutter analyze
flutter test --reporter expanded

# services/api
sh authlab/run-isolated.sh
go test -race -count=1 -p 1 ./...
go vet ./...
export AUTHLAB_MOBILE_FLUTTER="$(command -v flutter)"
sh authlab/run-mobile-isolated.sh

# 仓库根目录，macOS + Swift 命令行工具
sh packages/auth_vault/test/native/run-installation-marker.sh
```

Go 普通回归未设置 `AUTHLAB_MOBILE_FLUTTER` 时会跳过 Dart 联调，必须另跑 mobile runner。Dart 普通 `flutter test` 不包含 `integration/`；单独手动执行该文件但未设置 fixture 配置也只会跳过，不算通过。

Android 推荐准备模板指定 SDK／NDK 和 Java 17，先在 `apps/mobile` 做标准 `flutter build apk --debug --target-platform android-arm64`，然后在 `apps/mobile/android` 构建插件测试 APK：

```sh
./gradlew --no-daemon :hnuhole_auth_vault:assembleDebugAndroidTest
```

若只做本轮已审阅依赖的调试验证，可显式加 `-I prebuilt-debug.init.gradle -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart`；需要 Flutter 已生成 wrapper、`local.properties`、插件及 package 配置。完整应用仍应另做标准构建。安装生成的 `hnuhole_auth_vault-debug-androidTest.apk` 到专用测试设备后：

```sh
adb shell am instrument -w \
  -e class org.hnuhole.authvault.AndroidAuthVaultTest \
  org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner
```

跨进程探针使用 `AuthVaultProcessRestartTest` 和独立 namespace：

```sh
adb shell am instrument -w \
  -e class org.hnuhole.authvault.AuthVaultProcessRestartTest \
  -e vault_restart_phase write -e vault_restart_namespace native.restart.validation1 \
  org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner
adb shell am force-stop org.hnuhole.authvault.test
adb shell am instrument -w \
  -e class org.hnuhole.authvault.AuthVaultProcessRestartTest \
  -e vault_restart_phase read -e vault_restart_namespace native.restart.validation1 \
  org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner
```

同样分别执行 `kill-before-replace → read-before` 和 `kill-after-sync → read-after`，每对使用新 namespace。kill 阶段预期 instrumentation 中断，只有随后 read 阶段通过才是恢复证据；默认运行不会执行这些探针。所有设备测试只能操作专用测试包／测试 namespace。进程退出不等于设备断电，锁屏、Keychain／Keystore 错误、磁盘耗尽、备份恢复和重装仍须平台验收。

## 下一切片与清理

另一台电脑先补标准 Android 应用构建、上述设备执行及完整 Xcode／iOS 存储验收；随后接设备／恢复凭据管理页面与原生 Passkey。生产路由／迁移及业务授权统一经过 Gate、注销业务数据清理／通知、可信灾备与分权运营、独立人类安全评审仍未完成。

本轮大型临时 Flutter／Go／PostgreSQL 运行时、专用 Gradle／Go／Swift／pub 缓存、临时数据库与仓库内生成构建产物在收尾删除；只提交源码、可重跑脚本和小型验证记录。用户原有 Android SDK、AVD、系统 Java／Swift 与其他缓存不在清理范围内。下载依赖将在另一台电脑按其环境重新生成。
