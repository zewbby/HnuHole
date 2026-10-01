# Hnuhole Mobile

移动端认证状态机已接到原有 Material 入口树：旧号私有用户名／密码登录、V 校邮资格与 C 持钥注册、恢复码单次展示与隐藏后全量确认、独立恢复码重设、七天注销申请／状态核对、单设备接替提示、服务端权威会话恢复、活跃近到期续期及持久登出待办。

启动先处理登出标记并移除对应社区 Bearer；独立撤销待办异步重试，不拖住后来新会话。每次恢复均查 C；本地过期时间仅用于续期调度。401 清对应令牌／节点，503 保留令牌和导航位置并提供重试。所有秘密与未决能力由本地 [auth_vault](../../packages/auth_vault/README.md) 保存，无普通文件降级。新恢复码／密码只留短期内存，不缓存原码、不自动复制。

配置固定且不同的 C/V HTTPS origin（不得带路径、查询或响应指定的跳转地址）：

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=AUTH_COMMUNITY_BASE_URL=https://community.example.org --dart-define=AUTH_VERIFIER_BASE_URL=https://verifier.example.org
```

默认地址为 `.invalid`，需要运行实际隔离 C/V 公共服务。客户端验证固定帧／本地槽位和公钥绑定；权威严格票据验签由 C 执行，TLS 使用系统证书信任，不提供绕过按钮。每组固定端点使用独立安全存储 namespace／scope。

核心状态机的历史验证见[原报告](../../docs/design/auth-privacy-mobile-auth-validation-report.md)。2026-10-01 已完成真实客户端→隔离 C/V HTTPS／PostgreSQL 的认证联调，含未知结果、Gate 冻结／签名恢复和注销释放 ACK；运行 `services/api/authlab/run-mobile-isolated.sh`，需先 `flutter pub get` 并将 `AUTHLAB_MOBILE_FLUTTER` 设为 Flutter 可执行路径。普通 `flutter test` 不会执行这条联调。

Android 原生及 instrumentation 测试已编译并生成测试库 APK，尚未构建完整应用或执行设备故障测试；缺 NDK 时有显式受限调试入口 `android/prebuilt-debug.init.gradle`，默认／release 构建不改。iOS 标记同步与多 engine 串行修复已加入，本机只做 macOS 文件系统回归和 Swift 语法核对，缺完整 Xcode。正式签名未配置；通道后端仍是旧业务路由，尚未接到 authlab 的 Gate 授权。设备／凭据管理页面与原生 Passkey 继续待做。

用户要求大型临时运行时、专用缓存和生成 APK 收尾删除，只保留源码和小型证据。另一台电脑的完整复验步骤及平台边界见[本轮交付报告](../../docs/design/auth-privacy-mobile-native-integration-validation-report.md)。
