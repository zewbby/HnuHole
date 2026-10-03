# 原生 Passkey 桥

本包把 C 给出的 `publicKey` 选项交给 Android Credential Manager／iOS AuthenticationServices，再返回服务端契约的 WebAuthn JSON。私钥留在系统凭据提供方。Passkey 在本产品只证明恢复或凭据管理资格；系统成功后仍须 C 完成 challenge、RP/origin、签名、UV、会话／凭据版本及最终 Safety Gate 复核，不直接登录。

## Dart 契约

```dart
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

final PasskeyClient passkeys = NativePasskeyClient();
final attestation = await passkeys.create(serverOptions.publicKey);
final assertion = await passkeys.get(serverRecoveryOptions.publicKey);
```

`CancellablePasskeyClient` 增加 `cancel()`。关闭页面、退出、接替会话或离开恢复操作时取消原生请求，同时由应用自己的 token／operation fence 拒绝迟到结果。一个 client 的上一操作结算前，新的 create/get 返回 `PASSKEY_BUSY`；取消抑制旧结果，不能撤销系统已经创建的凭据。取消后的绑定未在 C 提交时，用户可在系统密码管理器删除该条孤立记录。

`PasskeyFailure.code` 为 `PASSKEY_CANCELLED`、`PASSKEY_UNAVAILABLE`、`PASSKEY_NOT_FOUND`、`PASSKEY_BUSY`、`PASSKEY_INVALID_OPTIONS`、`PASSKEY_INVALID_RESPONSE` 或 `PASSKEY_FAILED`。平台错误 message/details 不传入业务。取消不自动重试，新操作重新从 C 获取 challenge。创建成功后的提交未知用 C 的持久结果接口核对，不重新创建系统凭据。

输入仅接受现有固定策略：32 字节 challenge，随机 32 字节 `user.id` 与同值 `user.name`、固定非私有用户名的 displayName、ES256、UV required、resident required、attestation none、60 秒超时、最多 10 条排除项。恢复输入无用户名和 `allowCredentials`。未知输入字段（包括 origin/clientDataHash）拒绝。输出只有 `id/rawId/type/response/clientExtensionResults`；保留系统原始签名字节，摘要、attestation、clientData 均不落盘、不记录日志；非空扩展结果拒绝。

## 平台边界与打包

- Android 插件兼容 minSdk 23，原生 Passkey 操作要求 API 28+、可用系统／Play Services 提供方及屏幕锁。两条 AndroidX Credential Manager 依赖锁 `1.6.0`，采用 async callback + CancellationSignal，Activity／engine 脱离或 60 秒到期时取消。不会请求 SET_ORIGIN 或使用浏览器权限。[官方创建指南](https://developer.android.com/identity/passkeys/create-passkeys)、[稳定版发布记录](https://developer.android.com/jetpack/androidx/releases/credentials)（2026-10-02 查阅）。
- iOS 插件可链接 iOS 13+，运行 Passkey 要求 iOS 16+。排除列表非空时需要 iOS 17.4+；旧系统明确返回不可用，不忽略排除列表。使用当前 Flutter engine 的前台 window 呈现；进入后台、engine 脱离、显式取消或 60 秒超时后旧 delegate 回调失效。系统生成 clientData，桥不伪造 HTTPS origin。[Apple Passkey 文档](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)、[排除列表接口](https://developer.apple.com/documentation/authenticationservices/asauthorizationwebbrowserplatformpublickeycredentialregistrationrequest/excludedcredentials)、[取消接口](https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller/cancel%28%29)。
- iOS 提供 CocoaPods 和 SwiftPM，同一份源位于 `ios/hnuhole_auth_passkey/Sources/hnuhole_auth_passkey`；SwiftPM 产品名 `hnuhole-auth-passkey`，模块名 `hnuhole_auth_passkey`。Flutter 生成本地 FlutterFramework 依赖，未把 engine 二进制入库。[Flutter 插件迁移说明](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors)。

## 固定 RP 与应用关联

当前没有用户指定的真实 RP／受信域名／签名指纹／Apple Team ID，配置仍待提供。以下工具只从显式值生成待审阅文件，不修改宿主、不发布关联文件、不启用 WebAuthn。

在仓库根目录，先由操作者填入实际值；`PASSKEY_OUTPUT_DIR` 必须不存在：

```sh
python3 tools/configure-passkey-associations.py \
  --rp-id "${PASSKEY_RP_ID:?}" \
  --android-package "${PASSKEY_ANDROID_APPLICATION_ID:?}" \
  --android-cert-sha256 "${PASSKEY_ANDROID_CERT_SHA256:?}" \
  --ios-team-id "${PASSKEY_APPLE_TEAM_ID:?}" \
  --ios-bundle-id "${PASSKEY_IOS_BUNDLE_ID:?}" \
  --out "${PASSKEY_OUTPUT_DIR:?}"
```

单平台可以省略另一平台的两个参数；提供单侧一半、零指纹、非规范域或已有输出目录会拒绝。生成目录 0700、文件 0600。验证输入的人工归属仍由实际部署操作负责，工具不证明操作者拥有 RP 或签名身份。

### Android

1. 使用实际安装 APK 的 **签名证书** SHA256（Play App Signing 使用 app signing certificate，不能混用 upload key）。输出 `assetlinks.json` 与 C `webAuthn.androidOrigins` 中的 `android:apk-key-hash:<unpadded base64url SHA256>`来自同一指纹。debug、release 或轮换证书按批准范围分别审阅，开发证书不自动进入正式 allowlist。
2. 将 `assetlinks.json` 放在 `https://<RP>/.well-known/assetlinks.json`，HTTP 200、JSON Content-Type、无重定向；应用 package 必须等于安装 APK 的 applicationId。
3. 审阅后把 `android-passkey-associations.xml` 加到对应构建变体的 `app/src/.../res/values/`，把 manifest snippet 的 meta-data 加到同一变体的 `<application>`。文件只声明 credential association，不自动接管全部 web 链接。插件自身 manifest 不包含假 RP。[官方关联配置](https://developer.android.com/identity/credential-manager/prerequisites)。
4. C 显式应用生成的 WebAuthn fragment：固定 `rpId`、批准的 HTTPS origins 和 Android signing origins；普通 HTTP/CORS origin 白名单不能替代该策略。

### iOS

1. 在真实 RP 的 HTTPS `/.well-known/apple-app-site-association` 提供生成的 AASA，内容包含批准的 `<TeamID>.<BundleID>`，不附 `.json` 扩展名；配置正式关联域，TLS 链在设备受信。
2. 把生成的 `Runner.Passkey.entitlements` 放入相应宿主构建配置，Xcode 的 `CODE_SIGN_ENTITLEMENTS` 指向该文件；在 Apple provisioning profile 启用 Associated Domains。`webcredentials:<RP>`、C 固定 RP、AASA 与实际签名 app ID 对齐。默认项目不会链接空／假关联域 entitlement。
3. C 的 HTTPS origin 为批准的 `https://<RP>`；原始 clientData origin 由 AuthenticationServices 决定并由 C 对 allowlist 验证。[Apple 关联域说明](https://developer.apple.com/documentation/xcode/supporting-associated-domains)。

## 已有测试入口

包根目录，具备当前锁定 Flutter/Dart 和依赖时：

```sh
flutter pub get
flutter analyze
flutter test test/native_passkey_client_test.dart --reporter expanded
```

Dart 9 项测试是 MethodChannel contract／错误／取消替身，不证明设备 Passkey。Android 5 项 instrumentation 检验真实 Android Base64/JSON codec 和 ownership fence，仍不弹系统 Passkey UI。宿主完成标准 Flutter debug 构建并产生 wrapper 后，在 `apps/mobile/android`：

```sh
./gradlew --no-daemon :hnuhole_auth_passkey:assembleDebugAndroidTest
```

安装本轮目标／测试 APK 后，在专用设备：

```sh
adb shell am instrument -w \
  -e class org.hnuhole.authpasskey.PasskeyCodecTest \
  org.hnuhole.authpasskey.test/androidx.test.runner.AndroidJUnitRunner
```

iOS 4 项 XCTest 源码位于 `ios/hnuhole_auth_passkey/Tests/HnuholePasskeyCodecTests`，SwiftPM test target 同名，CocoaPods test spec 为 CodecTests；需完整 Xcode、Flutter 生成的本地 FlutterFramework、iOS 目标后执行，不以 macOS `swift test` 代替。包根还有可在已有 Swift CLI 的 macOS 执行的共享 Foundation codec 检查：

```sh
sh test/native/run-codec.sh
```

它编译真实 codec／ownership helper，临时二进制和 module cache 由 trap 删除；不链接 iOS AuthenticationServices 或 Flutter，不能算 iOS app／Passkey 通过。关联生成器的 5 项标准库测试，从仓库根运行：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests -p 'test_passkey_associations.py' -v
```

## 真机闭环待执行

| 场景 | 真机步骤与必须观察的结果 |
| --- | --- |
| 绑定／移除 | 密码复验→系统 UV→C 接受真实 attestation→清单新增；新鲜密码移除后该凭据的恢复 assertion 被 C 拒绝。移除仅撤 C 授权，不删除系统／同步提供方里的私钥，用户可在系统设置删除遗留条目。 |
| 可发现恢复 | 退出并杀进程；未输入用户名，选择 Passkey→真实 assertion→C 才显示账号／新恢复码→完整确认重设；不自动登录，所有旧凭据／会话被撤。另一台设备按已批准关联／同步身份复测。 |
| 用户取消／不可用 | 取消系统 sheet、无凭据／关闭屏幕锁／无提供方；不给 C 写入凭据、不显示已绑定、不重试旧 challenge，恢复码入口仍可用。 |
| 超时与迟到响应 | sheet 内取消／离开页面／切后台／旋转 Activity／engine 销毁后新登录；旧成功或错误回调不能更新新会话／页面。系统已创建而 C 未接收的孤立凭据按系统设置清理。 |
| 会话接替与 Gate | C 给挑战后另一设备接替或冻结，再完成系统 UI；C 最终拒绝，旧客户端无“绑定成功”。冻结后新恢复入口 fail closed；恢复后使用全新挑战。 |
| 提交未知与重启 | 丢弃绑定／移除／恢复码确认的 HTTP 响应，杀进程；原生安全存储恢复待办，仅查询原提交结果；不保存 attestation 或新恢复码原文，不重新注册系统凭据。 |
| 关联负向 | 错误RP、未批准签名证书、错误AASA TeamID/BundleID、证书链错误均拒绝；不能关闭 TLS、覆写 origin 或改弱 UV 让它“通过”。 |

记录 Android/iOS 设备与系统／提供方版本、实际签名与 RP 的脱敏引用、被测源码指纹、各场景结果；截图／日志不要包含恢复码、用户名、clientData、attestation、邮箱或 token。只用本轮归属的合成账号与凭据，结束后清理自己的系统测试凭据和构建产物。

2026-10-02 本机已执行共享 Swift codec／ownership 检查和生成器测试；Android/Dart/iOS XCTest／完整应用／系统 Passkey UI 未执行，缺 Flutter、Gradle／Android设备、完整 Xcode 与部署关联配置。具体命令退出码由本轮主交接记录登记。
