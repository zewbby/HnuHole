# HnuHole 图片查看 M1 技术验证
当前版本 0.0.0：独立技术样例，尚未完成 M2 正式组件。任务/需求见 [实施计划](../../docs/design/image-viewer-component-plan.md)，换机入口见 [机器交接](../../docs/design/image-viewer-machine-handoff.md)。

本次实际环境：Windows、Flutter 3.47.5（6a19cca56475dbfba1478ee68d7bd0c2ef891da1）、Dart 3.13.4。extended_image 10.1.0、gal 2.3.3、path_provider 2.1.5 已锁定；image 4.10.1 仅用于条件转换试验。两份 pubspec.lock 必须保留。独立样例约束不代表主 App 最低系统/SDK 已改变。

- lib/src/m1_viewer_probe.dart：复用 extended_image 缩放/平移和退出渲染、Flutter PageController 拖动/分页物理；集中记录手势开始资格。回顶同手势不退出/不进入退出动画，全部松手后的新下拉才可关闭。指针记录放在持续存在的页面层，避免切页销毁导致丢失松手事件。
- TickerMode 和页索引通知：当前页播放，inactive/paused、离页或访问失效停止；反复开关在路由退出动画完成后检查监听释放。宿主测试不能代证手机后台行为。
- lib/src/m1_save_probe.dart：gal 原文件写入，保存许可、防连点、错误/失效和自有临时文件清理；测试使用明确的 MethodChannel 替身，不能代证 Photos/MediaStore。
- tool/m1_animation_codec.dart：条件 GIF 实验，未导出为产品 API、未接入保存。映射有限/无限/一次播放，累计帧时序按 GIF 10ms 单位舍入；使用库的调色板/量化器保留二值透明，半透明默认拒绝。一次播放仅移除锁定编码器已知的循环扩展，布局变化会拒绝，需随依赖升级回归。
- example/：独立 Android/iOS App，Android applicationId 为 org.hnuhole.image_viewer_m1，iOS bundleId 为 org.hnuhole.imageViewerM1；本次未安装/运行手机。界面为技术工具，不是正式产品图稿。
- test/：36 项宿主聚焦测试。fixture 由 Pillow 12.3.0 生成，均为小型合成媒体；manifest.json 记录原始循环字段、帧时长、尺寸及 SHA256。GIF 的循环字段表示重复次数，WebP 表示总播放次数，不能直接互抄。

GIF 转换实验预算：输入≤1MiB、边长≤1024、≤30帧、累计≤400万像素、单帧≥20ms、周期≤60秒。这些是限制试验资源的门槛，**不是手机产品支持上限**。最终性能/尺寸/系统范围待设备测量。半透明、颜色量化和体积变化仍须产品决定，不默认降质或改存静态图。

在配置好 Flutter 的终端中，进入本包：
```powershell
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --machine --concurrency=1 | python -X utf8 tool/collect_test_results.py ../../docs/design/image-viewer-m1-host-test-results.json
dart run tool/measure_conversion.dart example/assets/fixtures/animation_benchmark.webp ../../docs/design/image-viewer-m1-conversion-benchmark.json
Set-Location example
flutter pub get
flutter analyze --no-pub
flutter build bundle --debug --no-pub
```
Python 只用于小型结果收集；普通运行可使用 flutter test --no-pub。重新生成 fixture 才需要 Pillow，已提交图片可直接测试。pub get 后检查两份锁文件，发生版本漂移先核对 SDK/镜像，不用新版本代证本次结果。

尚未实现 M2 统一业务接口、输入校验/来源解析/加载重试、按稳定 ID 保留阅读状态、旋转锚点、正式按钮/读屏/大字、受保护来源缓存策略。MIV01–MIV14 全面验收未完成；帖子、评论、私信接入在 M4。设备入口与待验矩阵见机器交接。
