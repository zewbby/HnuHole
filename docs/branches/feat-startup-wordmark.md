# 启动欢迎页字标

> **2026-10-27 本轮：**按用户要求将字标文字改为 `@SpeechFUL`；分支已基于最新 main 重放旧改动，并更新生成路径、SVG、辅助功能标签与记录。当前源码修改待验证、提交／推送／PR／合并；旧 r4 APK 仍显示旧字标，不能代表新版本。新版本的构建／设备验收需以后续 PR CI 和开发包交付为准。

- 工作项：AUTH-WORDMARK-01；模块 A12（启动欢迎展示）。
- 分支：`feat/startup-wordmark`，已改基于最新 `origin/main`（`b48e199`）。
- 更新：2026-10-27；本轮修改待验证、提交、推送、PR、合并，未发布。
- 范围：将蓝色大 Logo 下方文字替换为带 Threads 风格 @ 的 `SpeechFUL` 矢量字标，显示为 `@SpeechFUL`，粗斜体并保留紧凑字距；两行文案改为“在这里，”“想说就说”，第二行右移 48dp，整体右倾约 5.7°。蓝色 Logo 与认证行为沿用原实现。

字标以 Apache-2.0 Roboto Black Italic 轮廓生成，字距 -0.025em，@ 使用 CC0-1.0 Simple Icons 的 Threads 矢量轮廓。文字为 `SpeechFUL`，显示为 `@SpeechFUL`；文字高度 26dp，@ 高 30dp，与文字间距 6dp；画布宽度由生成器按字形计算，高度 30dp。浅色模式黑色，深色模式浅色。辅助功能标签为 `@SpeechFUL`。SVG 为可独立使用的透明背景矢量，Flutter 直接绘制同源路径，无新增运行时依赖。

源码：`apps/mobile/lib/src/auth/auth_wordmark.dart`、`auth_wordmark_path.dart`，欢迎页接入 `auth_presentation.dart`。设计源文件：`apps/mobile/assets/branding/speechful-wordmark.svg`，@ 源轮廓为同目录 `threads-symbol.svg`。来源、版本及许可见 `assets/fonts/NOTICE-Roboto.txt`、`LICENSE-Roboto.txt` 和 `assets/branding/NOTICE.txt`、`LICENSE-Simple-Icons.md`。

复现资源：安装 fonttools 后，下载生成器文件头指向的 `Roboto-BlackItalic.ttf`，运行 `python tools/design/build_startup_wordmark.py <字体文件>`，再执行 `dart format apps/mobile/lib/src/auth/auth_wordmark_path.dart`；生成器校验源字体 SHA-256。

验证：

- PASS：`flutter analyze --no-pub`，0 问题。
- PASS：r3 最终源码执行 `flutter test --no-pub test/auth_screen_test.dart test/auth_presentation_test.dart test/mobile_flow_theme_integration_test.dart test/startup_entry_test.dart`，32 项。另以既有 AUTH_UI_QA 字体与截图参数执行欢迎页单项；主题／语言切换、开始使用与启动回归通过。
- PASS：`flutter build bundle --debug --no-pub`。
- PASS：r3 的 375×812 浅／深色宿主渲染中新 @、缩小后的字标与错行微斜文案完整、可读。深色宿主动态主题截图中原大 Logo 的 serif 字形缺失，原因未确认；该 Logo 源码未改，截图不代证其设备显示，不能将缺字归因为已证实的缓存问题。
- NOT_RUN：APK 构建、手机安装及设备视觉确认，本次未请求设备交付。
- GitHub CI 未运行；现有 `auth-feedback.yml`、`feed-ui.yml` 会覆盖本改动的分析、认证／主题回归与 bundle 构建。

当前代码改为 `@SpeechFUL`；历史 r3/r4 图片仍是旧 `@hnuhole` 预览，不代表本轮设计。历史认证和整模块验收结论不提升。README 不变：本次为局部字标与文案调整，不改变项目能力、整体阶段、使用方式或主要在研工作。下一验收入口为本分支差异、定点回归与 PR 检查。
