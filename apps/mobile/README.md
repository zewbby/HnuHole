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

本轮验证使用临时 Flutter 3.47.5 / Dart 3.13.4，完整结果见[交付报告](../../docs/design/auth-privacy-mobile-auth-validation-report.md)。Android/iOS 工程与原生 vault 已加入；本机有 Android SDK／Java，缺完整 Xcode，调试构建因缺NDK 28.2.13676358失败，尚未生成APK／跑真机，也未证明断电落盘或平台备份行为。正式签名未配置。通道后端仍是旧业务路由，尚未接到 authlab 的 Gate 授权；真实客户端→真实 C/V PostgreSQL→目录的整链联调待下一切片。设备／凭据管理页面和原生 Passkey 桥接继续待做，现有数据不会被认证模块删除。
