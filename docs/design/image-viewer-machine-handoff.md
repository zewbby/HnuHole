# 图片查看组件换机交接
2026-10-10。GitHub分支：codex/image-viewer-component。首先阅读 [M1报告](image-viewer-m1-report.md)、[现行计划](image-viewer-component-plan.md)和台账 IV01。本次实际完成的是 M1 宿主技术样例，36项宿主测试通过；Android/iOS 原生构建与手机技术关未通过。M2/M3/M4尚未开始。

## 获取分支
新电脑在准备存放项目的目录执行：
```powershell
git clone --branch codex/image-viewer-component --single-branch https://github.com/zewbby/HnuHole.git HnuHole-image-viewer
Set-Location HnuHole-image-viewer
git branch --show-current
git log -1 --oneline
git status --short
```
预期分支名 codex/image-viewer-component，工作区干净。若已有该仓库且有未提交改动，先保留或建立独立worktree，不强制reset，不覆盖匿名/文字社区工作。

## 复现本机检查（不需要手机）
实际被测工具是 Flutter3.47.5/Dart3.13.4。先 flutter --version；版本不同须单列复验，不能沿用本次PASS。不复制已删除的本机缓存；两份锁文件和所有fixture均已提交。

Windows PowerShell：
```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = Join-Path $env:LOCALAPPDATA 'HnuHole-image-viewer-pub-cache'
Set-Location packages/image_viewer
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
Set-Location example
flutter pub get
flutter analyze --no-pub
flutter build bundle --debug --no-pub
git diff -- pubspec.lock ../pubspec.lock
```
预期：两个analyze无问题；36项测试通过；bundle成功；锁文件无版本/来源漂移。保留原image-viewer-m1-*证据，新版本/新设备生成新的记录，不覆盖成旧版本已通过。

Mac/Linux Bash（先从仓库根开始）：
```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_CACHE="$HOME/.cache/hnuhole-image-viewer-pub"
cd packages/image_viewer
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
cd example
flutter pub get
flutter analyze --no-pub
flutter build bundle --debug --no-pub
```
Pillow只在重生成fixture时需要；本次使用12.3.0，现有图片可以直接测试。Python结果收集和Dart量测命令见包README。资源数据仅桌面样本，不能当手机预算。

## 下一步平台构建与M1验收
独立示例 Android applicationId：org.hnuhole.image_viewer_m1，iOS bundleId：org.hnuhole.imageViewerM1。不要覆盖原 HnuHole 匿名验收App。Android Gradle9.3.1/AGP9.1.0/Kotlin2.4.0 缓存本机没有建立；下一台具备工具链再构建。iOS需要Mac/Xcode及签名配置。

在 example 中：
```text
flutter build apk --debug --no-pub
flutter build ios --debug --no-codesign --no-pub
flutter test integration_test/image_viewer_device_test.dart -d <专用设备ID>
```
第一条仅Android，第二条仅Mac/iOS。第三条默认只做严格长图技术场景；保存测试默认SKIP，需明确安排设备操作者和相册核对后使用：
```text
flutter test integration_test/image_viewer_device_test.dart -d <专用设备ID> --dart-define=M1_EXPORT_FIXTURES=true
```
该选项会主动导出本任务GIF/WebP合成图片并可能触发系统权限对话框；插件返回成功也不是相册动画回放PASS。

需分别记录 Android、iPhone 的设备/系统/App源码SHA及以下结果：
1. 普通图/长图/多图真实触摸：适宽顶部、回顶同手势没有退出动画、全部松手后新下拉、双指/双击/取消、缩放不误切图、首尾。
2. GIF和动态WebP：连续切图、实际前后台、关闭和访问失效后非当前图片停止；反复开关，无迟到界面污染。
3. 原文件保存：允许/禁止、拒绝/撤销权限、重复点击、保存中关闭/失效、空间或格式失败；输出文件SHA/帧数/时长/循环与原始来源核对。
4. 系统相册回放：GIF和动态WebP分别在目标相册实际播放；记录照片可导入、文件动画完整和相册回放三种证据，不能只看缩略图。
5. 核对 gal iOS 文件导入强制解包风险；必要时比较公开字节API，不能靠Dart替身推断不会崩溃。
6. 只有原格式实际不满足目标相册时才评估兼容。工具中二值透明、循环与时序适配已试验；半透明默认拒绝。兼容质量、手机峰值/耗时/体积和提示语需具体决定，未批准默认转换。

M1退出条件仍需双端技术证据。M2统一接口、错误来源/重试/稳定ID阅读状态、旋转、正式UI/读屏/大字与受保护来源隔离尚未实现；M3正式验收、M4三类业务接入不可记为仅差设备测试。按AGENTS同步四份交接文档与IV01/MIV记录。

## 本机清理边界
只删除本次自有 D:/zewbbyTest/Hnuhole-image-viewer-m1-20261010 缓存和 packages/image_viewer 下本次生成的 build/.dart_tool、本机插件/平台配置。保留现成Flutter/Android/JDK、其他pub/Gradle缓存、AVD、用户数据、其他工作树。实际结果见 image-viewer-m1-verification.json 的 cleanup。下次运行先pub get，Android必要时重新生成被gitignore忽略的wrapper启动文件。


2026-10-10 交付记录：M1源码与交接已推送到 `codex/image-viewer-component`，源码提交 `c500788fa99a571cb67f8c4a663e9e4da2c11411`，已核对远端SHA。后续交接元数据提交以远端分支最新HEAD为准。缓存删除被自动审批检查拒绝（blocked by policy），未执行删除；本任务5个缓存/构建目录共253787594字节仍保留。准确路径和状态见 `image-viewer-m1-cleanup.json`；源码、锁文件和合成测试图片已入库，换机不依赖这些缓存。M1平台关卡仍待执行，正式组件尚未验收。
