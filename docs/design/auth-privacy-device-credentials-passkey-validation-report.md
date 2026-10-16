# 设备、恢复凭据管理与原生 Passkey 实施／验证记录

日期：2026-10-02（Asia/Shanghai）。状态：**用户操作流程和平台桥源码已写入工作区，编译、动态数据库及真机验收待执行；平台关联配置待提供。**按[本片任务单 D0–D6](auth-privacy-device-credentials-passkey-plan.md)实施，不将源码完成计为验收 PASS。

## 基线与实现

只在 `codex/auth-privacy-handoff`，实际 checkout `/Users/zewbao/Desktop/workspace/Hnuhole/remote-auth-privacy-handoff`，HEAD `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`。保留此前 T0–T6 和模块验收文档的未提交改动，本片未提交／推送。当前源码摘要和命令结果见[小型机器记录](../../services/api/authlab/device-credentials-passkey-verification.json)；[模块台账](module-acceptance-ledger.json)更新 B01/N03/A09 及受影响模块，不改历史报告的通过版本。

| 用户要求 | 已写源码 | 证据边界 |
| --- | --- | --- |
| 当前／最近接替设备与主动退出 | `security_management_screen.dart`／controller、`HttpAuthApi.devices`，main“我的”打开管理页；复用原持久登出标记＋独立定向撤销 | Widget 与真实 HTTPS fixture 源码；Flutter 未执行 |
| 恢复码轮换 | 新鲜密码、新码仅内存一次展示、隐藏后完整重输；发送前持久原意图／键；只读原结果、终态确认和旧会话核对分流 | 28 个管理 controller 场景、8 项 HTTP 契约新增／更新；SQL/HTTPS、丢响应及 headless 重建测试未执行 |
| 原生 Passkey 绑定／移除／可发现恢复 | 新 `auth_passkey`，Android Credential Manager／iOS AuthenticationServices；管理器密码复验＋两步移除；AuthFlows 原生 assertion 接现有受限密码重设；不自动登录／取消注销 | Dart、Android instrumentation、iOS XCTest 源码；没有系统 sheet 或真实签名闭环证据 |
| 存储／重启／接替／冻结／迟到结果 | 新设备 integration_test、iOS Keychain RunnerTests；同 token／请求版本和登录开始的 authorityVersion fence；仅取消本流程拥有的 native sheet；最终 Gate 的结果查询 | macOS 共享 codec／marker 实跑；设备／Go／Dart 源码未执行。headless 重建不代证 OS 进程重启 |

服务端新增 `GET /api/v1/auth/credential-change-result`：Bearer＋原 `Credential-Change-ID`／`Idempotency-Key`，只返回 PENDING／COMMITTED／NOT_COMMITTED 和权威截止；三态均 HTTP200。仅已知终止或同事务不可逆终止意图可判未提交，缺记录／异键不推断失败。原持久结果保存8天，之后永久墓碑返回410，不重放新码或证明。复用正式意图／挑战／结果结构，未增加迁移或扩大运行权限。

固定 `webAuthn:{rpId,origins,androidOrigins}` 由部署配置提供，C 才显式装配 `WithWebAuthn`；省略／null 保持 Passkey 禁用，V 拒绝该配置。Android 签名 origin 独立批准，严格 `android:apk-key-hash:<32字节规范base64url>`，不从 HTTP/CORS 推导；iOS 使用批准的 RP HTTPS origin 及应用关联域。政策摘要序列化变化会使更新前待提交挑战失效，要求重新取挑战；已提交事实仍保留。

独立源码复核促成修正：核对 PENDING 的 HTTP200 契约、跨账号已消费挑战的锁顺序、登录开始后尚未写新 token 时的原生迟到结果、等待 HTTP 时误取消其他拥有者 sheet、首次安全存储读取／初始通知期间的路由取消，以及底层认证页误弹出顶部管理页。新增相应 barrier／嵌套路由用例；缺工具，未获得这些修正的 red／green 动态证据。

## 本次实际检查

平台沿用 macOS 26.2 arm64、CommandLineTools；没有完整 Xcode、Go/gofmt、Flutter/Dart、Docker/PostgreSQL 或可用设备验收环境。未下载 SDK／镜像／工具，未创建数据库、开发私钥或 APK。

| 实际命令 | 结果 | 证明范围 |
| --- | --- | --- |
| `git diff --check` | PASS／0 | 补丁空白 |
| 已有 Anaconda Python `check-specs.py --yaml-only` | PASS／0，三份契约 | YAML／本地引用／结构，不是完整 OpenAPI validator |
| 完整 `check-specs.py` | BLOCKED／1 | 缺 `openapi-spec-validator`，完整规范验证未执行 |
| 关联生成器 unittest | PASS／0，5项 | 显式身份／RP校验、平台关联内容、私有目录和拒绝覆盖；未发布关联 |
| `sh packages/auth_passkey/test/native/run-codec.sh` | PASS／0 | 真实共享 Swift codec／取消归属，未链接 iOS AuthenticationServices／Flutter |
| `sh packages/auth_vault/test/native/run-installation-marker.sh` | PASS／0 | macOS marker、同步重试、损坏与重装边界，非 iOS Keychain |
| Swift parse／podspec Ruby syntax | PASS／0 | 语法；不是 iOS 类型检查或插件链接 |
| `go test -race -count=1 -p 1 ./...` | BLOCKED／127 | 缺 go；SQL／编译／race 未执行 |
| Flutter 聚焦测试／`flutter analyze` | BLOCKED／127 | 缺 flutter；页面、API、围栏及设备测试未执行 |

新增测试源码还包括：服务端12个 Test函数（SQL7、HTTP2、原生 origin1、runtime政策1、authdev政策1），原HTTPS/SQL端到端与CORS回归；恢复流程11项、管理页面4项、嵌套认证路由1项；native包Dart channel9项、Android codec/ownership5项、iOS codec4项。测试数量不代表通过数。

## 后续验收入口

先按原 runtime 报告复用现成工具／一次性库，格式化 Go/Dart 并固定被测源码指纹。仓库根完整 OpenAPI validator 及全部 Go/Flutter 回归仍须执行；普通无DSN Go或跳过 Flutter fixture不能计SQL／联调通过。

```sh
# apps/mobile；先 flutter pub get，再执行
flutter analyze
flutter test --reporter expanded

# packages/auth_passkey；先 flutter pub get
flutter analyze
flutter test test/native_passkey_client_test.dart --reporter expanded

# services/api；拥有现成工具和隔离数据库资源
sh authlab/run-isolated.sh
go test -race -count=1 -p 1 ./...
go vet ./...
export AUTHLAB_MOBILE_FLUTTER="$(command -v flutter)"
sh authlab/run-mobile-isolated.sh
```

本轮 mobile fixture 使用真实 TLS handler／C/V SQL测试新管理读取、轮换确认后丢响应、原结果查询、接替及冻结；`restartClient()`仍是同进程对象重建＋内存 `_LabVault`，不调用原生 Passkey。实际非owner cmd＋移动平台组合还须按A02/A13复验。

### 原生安全存储和真实进程

新增 `apps/mobile/integration_test/auth_security_device_test.dart` 直接调用真实平台 vault，不替换 MethodChannel；它的授权API是有意不授权的替身，仅验证本地登出围栏与原核对键。先在专用手机／模拟器从 `apps/mobile` 执行：

```sh
flutter test integration_test/auth_security_device_test.dart -d "${AUTH_TEST_DEVICE:?}"
```

两进程探针需同一个唯一 `native.security.test.*` namespace，分别用 `--dart-define=AUTH_DEVICE_PHASE=write`／`read` 和 `--dart-define=AUTH_DEVICE_NAMESPACE=...` 启动该 test；两次之间明确停止 app，保持安装数据，不能卸载／清应用数据。read 必须看到不同 PID、原登出标记和核对键；它才证明跨进程，而非只建新对象。Android可使用测试包的明确 applicationId force-stop；iOS需确认构建／安装流程保留本次数据。read后仅写空本轮namespace；不碰用户现存vault。

iOS `RunnerTests.swift` 已替换空example：真实Keychain跨plugin实例、ThisDeviceOnly／非同步属性、错误／超大写不覆盖，以及显式两XCTest进程write/read探针。完整 Flutter/Xcode 构建后在 RunnerTests 目标执行；跨进程通过方案环境变量 `AUTH_VAULT_RESTART_PHASE`／`AUTH_VAULT_RESTART_NAMESPACE` 单独两次启动，不并行同namespace。首次解锁、锁屏、Keychain不可用、磁盘满、备份／重装残留等真实故障仍按N01/N02测试交接逐项执行。

`auth_vault` 与 `auth_passkey` 已使用同源 SwiftPM/CocoaPods 打包；旧 vault source 路径为相对symlink便于追溯。Flutter生成 FlutterFramework 后必须编译完整 iOS app和RunnerTests；本轮parse/marker不能证明SwiftPM链接。Android仍需标准完整app构建、现有vault instrumentation及新Passkey codec instrumentation，不用测试库APK代证app。

### Passkey 关联配置与真机闭环

用户回答尚无 RP 域名、Android签名证书、iOS Team／Bundle配置。`tools/configure-passkey-associations.py` 只从显式值生成待审阅 AASA、assetlinks、Android资源／manifest snippet、iOS entitlement和runtime政策片段；不自动部署或启用。具体命令、平台最低版本及正负向真机矩阵见[原生包说明](../../packages/auth_passkey/README.md)。系统绑定／移除后的真实恢复、关联错误、UV取消、会话接替／Freeze在途、响应丢失杀进程、旧证明迟到与同步换机必须独立取得设备证据。

本片只有源码与小型记录；Swift测试二进制／module cache及关联生成测试目录已由各自trap／临时目录清理。没有清理未知容器／SDK／用户数据。生产运营、V独立Gate、独立授时／锚点及人类安全审计仍不由本片代证。
