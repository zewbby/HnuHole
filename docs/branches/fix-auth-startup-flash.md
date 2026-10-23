# AUTH-STARTUP-FLASH-01 启动中间错误页闪现

- 2026-10-23，分支 `codex/fix/auth-login-startup`，基线 main `93d3ed6`；已通过[PR #56](https://github.com/zewbby/HnuHole/pull/56)合并main `4197dd3`，同签2308整合包已构建，未安装。
- 用户将范围收窄为仅修复视频里的启动闪页。账号密码、登录错误分类与诊断修改已撤回。
- 视频约4秒时出现旧的“会话暂时无法确认／重新核对会话”页，随后进入欢迎页。原因是 `AuthSessionController.start` 在读取本地状态之前调用 directory.suspend，入口把恢复中的临时状态展示为失败。
- 主入口将 starting/restoring 状态传给 EntryScreen，恢复阶段保持欢迎页，读取完成后继续既有路由。真实认证失败、授权围栏和已认证后的通道错误恢复不改。
- 源码：`apps/mobile/lib/main.dart`、`apps/mobile/lib/src/navigation/entry_screen.dart`。
- 回归：`startup_entry_test.dart`、`login_home_navigation_test.dart`、`personal_route_account_test.dart`共21项PASS；`flutter analyze --no-pub`零问题。
- Windows测试临时使用本机SQLite系统DLL钩子，结束后已恢复pubspec；锁文件无变更。日志和视频抽帧在 `E:/Hnuhole-env/deliveries/auth-login-startup-20261023/`，不纳入Git。
- 未覆盖安装手机，保留其他任务整合版本；下一步将这项小范围改动纳入整合包再做VIVO视觉验证。README不变：既有启动展示修正，无项目能力或入口变化。

## 合并交付回执

- PR #56最终七类CI全部通过；2308包的产品源码与合并后main逐文件差异为空。21项入口／导航回归PASS，分析0。
- APK：`E:/Hnuhole-env/deliveries/HnuHole-main-2026102308.apk`。未安装，VIVO视觉待验；未发布生产。上方待提交／待整合文字为历史快照。
