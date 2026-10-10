# 图片查看组件 M1 宿主验证与交接
日期：2026-10-10（Asia/Shanghai）。分支：codex/image-viewer-component；起点 0eff47a21cd4f4ab1636b4468f7d5df9769a264f。当前为 **M1 本机可执行部分完成，平台技术关未完成**；IV01 是部分实现，不是“完整组件只差验收”。

## 已实现与实际执行
独立源码/示例/测试在 packages/image_viewer/。主 App、认证、服务端、SQL、其他工作树没有接入本组件。依赖与源码指纹见 [机器记录](image-viewer-m1-verification.json)，逐项宿主结果见 [36项记录](image-viewer-m1-host-test-results.json)。

| 检查 | 实际结果 | 证明范围 |
|---|---|---|
| 本包及示例 flutter analyze --no-pub | PASS | 当前 Dart 源码与设备测试入口静态分析 |
| flutter test --no-pub --machine --concurrency=1 | PASS，36项 | 16项手势/生命周期、12项保存替身、8项解码/转换；Windows Flutter tester |
| 示例 flutter build bundle --debug --no-pub | PASS | Dart/kernel 与资源编译，不包含 Android/iOS 原生链接或安装 |
| 原始动图保存替身 | PASS | 字节与扩展名原样到达 gal、错误、防连点、写入前/后失效、临时文件清理 |
| 条件 GIF 解码/循环/时序/透明试验 | 有范围 PASS 与已复现质量差异 | 转换未用于产品；半透明安全路径拒绝，不能称完全等价 |
| 桌面转换量测 | 已执行 | 单样本 Windows Dart 进程，不是手机预算 |
| 许可证/依赖/平台配置检查 | 已执行 | 锁定发布包源码、许可证和配置；不代证原生构建 |

## 选型与适配结果
extended_image 10.1.0（MIT）提供图片缩放/平移与退出渲染；gal 2.3.3（BSD-3-Clause）提供原生保存；image 4.10.1（MIT）仅为兼容实验；path_provider 2.1.5（BSD-3-Clause）取得自有临时目录。[依赖记录](image-viewer-m1-dependency-audit.json)列出实际解析依赖及关键包约束。当前传递 path_provider_foundation 2.6.0 要求 Flutter≥3.38.4；不以顶层包宽松下限推断旧 SDK 兼容。

严格长图规则不能仅配置“允许下拉”：长图适宽基准可能大于1，内置分页/退出判定也存在尺度假设。本样例使用库公开 slide/endSlide 渲染退出，Flutter 公开 ScrollPosition.drag/PageController 处理分页，自己记录单指、方向、顶部、基准尺度与松手资格。没有 fork、修改依赖源码、自研解码器或原生相册桥；但维护了一层实际指针适配，仍需要手机触摸回归，不能称零适配。

复现并修正：回顶同手势退出风险、多图切换中子页面销毁丢失松手记录、页缓存导致动图可见性更新不可靠。宿主测试验证读取回顶无退出变换、新下拉关闭、双指/缩放不误切图、双击、取消、首尾、双向切图、阅读方向锁定以及动图后台/切页/关闭/撤销。暂停测试遵循 inactive→paused→resumed，反复关闭等待真实路由退出动画结束。

## GIF 兼容不是无损替代
直接 image.encodeGif 会把 WebP 有限循环总播放数误当 GIF 重复数；原WebP播放两次，直接转换GIF会播放三次。实验已映射循环，针对一次播放移除锁定编码器的已知循环扩展，Flutter 实际解码器验证有限/无限/一次播放一致。37/53/87ms 示例变成40/50/90ms，周期误差3ms；采用累计舍入，实验周期误差≤5ms。

默认量化器还会丢失透明度。实验通过公开量化器与 RGBA 调色板保留二值透明；半透明输入默认拒绝。诊断路径可复现损失，只用于分析，未接保存流程。[动画记录](image-viewer-m1-animation-analysis.json)保留实际差异，不把“复现差异的测试PASS”当作质量通过。

[桌面量测](image-viewer-m1-conversion-benchmark.json)：320×180、12帧，17,006字节 WebP→344,398字节 GIF，约20.25倍；本次969ms。进程峰值 RSS 约377.5MiB，包含 Dart VM、JIT 与库，不等于转换单独峰值或手机占用。样本原始RGBA下界约2.64MiB，不能从下界推出实际内存。试验资源门槛见 README；尚未固定产品手机预算。

## 平台剩余技术关
| 未执行项 | 状态与原因 | 下一步 |
|---|---|---|
| Android 原生 APK 编译/链接 | BLOCKED：现成 Gradle9.3.1/AGP9.1.0/Kotlin2.4.0缓存不存在；遵守不自动恢复大型缓存要求 | 有完整工具链的电脑构建独立示例 |
| iOS 编译/链接 | BLOCKED：本机Windows，无macOS/Xcode | Mac执行独立示例构建 |
| Android/iPhone真实触摸、后台、权限、保存/相册回放 | NOT_RUN：用户要求本轮不参与手机 | 专用示例App，两端分别补证据 |
| 半透明GIF兼容及手机转换预算 | NOT_RUN／兼容未批准 | 先确认原格式相册回放是否失败，再就具体可见取舍决定 |
| M2正式封装、M3完整双端验收、M4业务接入 | NOT_STARTED | 依完整计划推进，技术样例不能代替成品 |

Android示例继承本次Flutter配置：minSdk24、compile/target36；仅添加 WRITE_EXTERNAL_STORAGE maxSdk28。iOS示例部署15.0、只有相册添加用途说明；未申请纯查看读取权限。未改变主App最低系统或权限。

gal发布源码 Android 复制原文件字节；Darwin 路径使用 Photos 导入。iOS文件路径中存在 creationRequestForAssetFromImage(...) 强制解包，对不支持格式存在待核对的崩溃风险；本次未复现设备崩溃，替身错误测试也不能覆盖它。插件返回成功、文件动画完整、系统相册实际动画回放是三份不同证据，不能相互推断。

## 换机与清理
优先读 [机器交接](image-viewer-machine-handoff.md)、[计划](image-viewer-component-plan.md)、模块交接和台账。保存原文件为默认，GIF兼容未启用；未借用原vivo匿名App或服务。本次提交/推送经用户明确授权，实际远端SHA以Git历史/交付记录为准。自有pub缓存、两级build/.dart_tool及生成的本机配置在发布交接后清理，实际删除清单记录在机器记录。源码、锁文件、合成fixture和小型证据保留。
