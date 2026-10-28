# 欢迎图案、启动衔接与桌面图标

- 工作项：AUTH-WELCOME-QUOTE-01；模块 A12（启动欢迎展示）。
- 日期：2026-10-28；分支：`codex/feat/welcome-mascot-logo`，基于原欢迎页字标实现。
- 状态快照（2026-10-28，合并前）：实现已提交并推送 [PR #88](https://github.com/zewbby/SpeechFUL/pull/88)，远端产品 CI 进行中，待全通过后按用户已有授权合并；最终合并事实以该 PR 为准，未生产发布。
- 欢迎图案：从用户图稿抠出透明安静手势，去掉蓝色圆底，浅色黑线、深色白线，图案 126×126dp，保留原 150×150dp 布局区域。
- 桌面图标：Android legacy/adaptive/monochrome 与 iOS 全尺寸图标采用黑底白标；普通图标留约 30% 空白，Android adaptive 前景可见区域为 65×62dp，落在 66dp 安全区内。
- 启动：Android 四套 LaunchTheme 关闭独立系统预览并限制透明性在启动主题；NormalTheme 保持不透明。Flutter 先解码图案并画出完整欢迎页，之后创建运行时，恢复／目录加载期间保持同一页，仅隐藏主题、语言及开始三个控件；就绪后以 520ms 淡入和轻微位移动画出现，品牌位置固定。
- 题词：两行“『愿为江水，与君重逢；／同归沧溟，共载长风』”，第二行对齐到“愿”字，字标下方间隔增加 6dp；英文界面提供对应译文。认证、存储与会话策略保持原实现。
- 源码：[auth_presentation.dart](../../apps/mobile/lib/src/auth/auth_presentation.dart)、[welcome_at_mark.dart](../../apps/mobile/lib/src/auth/welcome_at_mark.dart)、[welcome-shush-mark.png](../../apps/mobile/assets/branding/welcome-shush-mark.png)、[Android 图标资源](../../apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml)、[iOS 图标集](../../apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json)。

## 验证

- PASS：`flutter analyze --no-pub`，0 问题。
- PASS：`flutter test --no-pub --reporter expanded test/auth_screen_test.dart test/email_login_test.dart test/auth_session_controller_test.dart test/startup_entry_test.dart test/login_home_navigation_test.dart test/personal_route_account_test.dart`，92 项。首轮两项仍期待旧 feed 启动壳而失败，按新需求改为欢迎品牌固定／控件隐藏断言后，整组重跑通过。
- PASS：上述测试额外提供 `AUTH_UI_QA_DIR`、本地中文及图标字体参数，输出无控件加载态、浅色与深色预览至 `E:/Hnuhole-env/welcome-mascot-preview/`；它们是 widget 截图，不代替真机结论。
- CI 首轮 FAIL：`flutter`／`flutter-and-real-feed` 中的三项旧测试仍假定同步 main／按钮立即可点击。按异步图片预载和控件入场时序更新测试等待；根节点仍为真实 `HnuholeApp`，TalkBack 仍验证 tap action 并触发真实回调。`flutter test --no-pub test/b5_candidate_root_test.dart test/telegram_appearance_test.dart test/talkback_semantics_test.dart` 8 项 PASS；没有为此改动产品行为或降低断言。
- PASS：`flutter build apk --debug --no-pub`；使用已有设备测试签名、`HNUHOLE_PRERELEASE_DEVICE=1` 生成同包名 APK。Gradle 缓存、Java 临时目录及 SDK 使用 E 盘；最初 C 盘空间错误及签名不一致的安装失败保留为过程结果，未卸载或清除用户数据。
- PASS：Android 15 vivo V2323A（`10CEAG17RY003M7`）`adb install -r` 与显式 `am start -W -n org.hnuhole.hnuhole_mobile/.MainActivity`。用户已认可启动衔接及最终无蓝底黑／白轮廓版本。
- PASS：真机冷启动录屏 `E:/Hnuhole-env/welcome-mascot-preview/welcome-explicit-start-vivo.mp4` 验证完整品牌首帧与三个控件入场，无单独居中圆标页。该证据录于去蓝底前，最终轮廓用浅深预览及新 APK 安装记录核对。
- PASS：独立只读 agent 审查；Android bitmap 缩放及冷首帧图片预解码问题已修复并复核。agent review 不等于 GitHub 成员批准。
- PASS：最终去蓝底版本 vivo 浅深主题截图 `E:/Hnuhole-env/welcome-mascot-preview/welcome-outline-light-vivo.png`、`welcome-outline-dark-final-vivo.png`，已确认浅色黑线与深色白线；启动前读取外观偏好并让 bootstrap／运行时共用同一控制器，避免暗色用户冷启动闪浅色。
- PASS：`git diff --check`。
- NOT_RUN：iOS 构建及真机（Windows 环境无 Xcode）；仅更新图标、透明 template 启动图及动态颜色。其他 Android 厂商／版本未扩展验收。
- 待完成：[PR #88 适用产品 CI](https://github.com/zewbby/SpeechFUL/pull/88/checks)、合并；此记录不提升 A12 整模块或生产验收结论。
