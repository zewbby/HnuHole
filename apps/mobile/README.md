# Hnuhole Mobile

移动端认证状态机已接到原有 Material 入口树：旧号私有用户名／密码登录、V 校邮资格与 C 持钥注册、恢复码单次展示与隐藏后全量确认、独立恢复码重设、七天注销申请／状态核对、单设备接替提示、服务端权威会话恢复、活跃近到期续期及持久登出待办。

启动先处理登出标记并移除对应社区 Bearer；独立撤销待办异步重试，不拖住后来新会话。每次恢复均查 C；本地过期时间仅用于续期调度。目录 200 必须包含完整七通道与严格 UTC `Session-Expires-At`；同 token／请求版本仍有效时，先将权威截止写入 AuthStore 并核对落盘，才发布节点。同 token 的并发迟到响应不能缩短已持久截止。登录、恢复、退出及新目录请求立即使旧请求失效；截止缺失／非法、目录不全或持久写失败均不发布节点。401 清对应令牌／节点；503、网络故障和公共边界 400／403／429 保留安全持久令牌、隐藏节点并提供前台重试。不存在后台定时保活。所有秘密与未决能力由本地 [auth_vault](../../packages/auth_vault/README.md) 保存，无普通文件降级。新恢复码／密码只留短期内存，不缓存原码、不自动复制。

配置固定且不同的 C/V HTTPS origin（不得带路径、查询或响应指定的跳转地址）：

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=AUTH_COMMUNITY_BASE_URL=https://community.example.org --dart-define=AUTH_VERIFIER_BASE_URL=https://verifier.example.org
```

默认地址为 `.invalid`，需要运行实际隔离 C/V 公共服务。客户端验证固定帧／本地槽位和公钥绑定；权威严格票据验签由 C 执行，TLS 使用系统证书信任，不提供绕过按钮。每组固定端点使用独立安全存储 namespace／scope。

核心状态机的历史验证见[原报告](../../docs/design/auth-privacy-mobile-auth-validation-report.md)。2026-10-01 历史联调完成真实客户端→隔离 C/V HTTPS／PostgreSQL 的认证请求，含未知结果、Gate 冻结／签名恢复和注销释放 ACK，当时目录使用 503 占位。本次 fixture 已换为真实 `HttpChannelRepository`、受信 TLS 和 C Gate 目录，断言七节点及 AuthStore 持久截止；此更新尚需在有 Flutter 的电脑实际复验。运行 `services/api/authlab/run-mobile-isolated.sh`，需先 `flutter pub get` 并将 `AUTHLAB_MOBILE_FLUTTER` 设为 Flutter 可执行路径。普通 `flutter test` 不会执行这条联调。

Android vault instrumentation 在历史版本曾编译／组装测试库 APK，当前完整app和设备故障验收待执行；受限 `android/prebuilt-debug.init.gradle` 不代证新增 Passkey 插件。iOS vault标记、串行和SwiftPM/CocoaPods同源打包已接入，当前完整Xcode／Keychain／插件链接未验。正式签名与关联域未配置。

## 设备与恢复凭据管理（2026-10-02）

“我的”进入当前／最近接替设备与恢复凭据页：主动退出、密码复验后恢复码轮换、一次展示／隐藏／完整确认、可选Passkey绑定和两步移除。登录页可发现Passkey证明接现有密码重设，不自动登录。权威截止先落盘；最终提交前保存原意图与键，未知结果只读核对，不保存密码、新码或系统证明。

原生桥、平台关联生成及真机矩阵见 [auth_passkey](../../packages/auth_passkey/README.md)。用户尚无RP／签名／Team配置，系统Passkey真机闭环待验。新增真实vault／跨进程入口为 `integration_test/auth_security_device_test.dart`，iOS RunnerTests直接测试Keychain；步骤见[本片报告](../../docs/design/auth-privacy-device-credentials-passkey-validation-report.md)和[模块交接](../../docs/design/module-acceptance-handoff.md)。本机共享Swift codec／marker、关联生成器及轻量检查通过；Go／Flutter／SQL／完整app与设备未验。

用户要求大型临时运行时、专用缓存和生成 APK 收尾删除，只保留源码和小型证据。另一台电脑的完整复验步骤及平台边界见[本轮交付报告](../../docs/design/auth-privacy-mobile-native-integration-validation-report.md)。
