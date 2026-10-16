# HnuHole 独立图片查看组件

> **2026-10-15 当前交付：**Android 10/API29 起默认启用原文件保存，iOS 默认关闭，两个平台独立决策。包112＋示例7、分析、bundle、ARM64 debug/release构建和验签通过；S18/API35实际Release 20263021完成47项真实解码/资源检查，补齐有限/无限WebP保存字节与结算清理。TalkBack保留此前人工通过，不重复测试。见[本轮报告](../../docs/design/image-viewer-android-saving-report.md)。下方有日期的段落保留历史状态。

> **本轮Android证据：**包108＋示例5、分析/bundle/两份原生构建通过；S18/API35实际20263019，修复缩放旋转并固定资源边界。原格式保存及选定Fossify回放通过；默认保存关闭、iOS与未取证子项单列，见[收尾报告](../../docs/design/image-viewer-android-completion-report.md)。下方旧日期记录保留原证明范围。

> **当前 Android 基线（2026-10-14）：**最低 Android 10 / API29，所有设计遵循 [ADR 0006](../../docs/adr/0006-android-platform-support.md)，不再适配旧系统。示例已移除旧存储权限，保存仍须调用方显式启用。原文件保存与外部相册回放分别验收；vivo Gallery9.4.6.13存在已复现缺陷，Fossify1.14.0已有版本限定证据。

## 资源契约

`ViewerController.resourceLimits` 默认使用 `ViewerResourceLimits`：查看输入不超过16MiB；静态图不超过12×1024×1024像素、任一边16384；动画每帧不超过1024×1024像素、最多120帧，尺寸×帧数不超过16×1024×1024像素；单帧时长不超过15秒、单轮不超过60秒。保存协调器 `maxOriginalBytes` 默认16MiB。超限明确反馈 `ViewerFailure.resourceLimit` / `ViewerSaveStatus.resourceLimit`，可关闭或切图；没有缩图、删帧、改循环或转格式。

原始 provider 仍由调用方授权。标准 Flutter ImageProvider 必须使用 supplied decoder callback，才能在首次帧解码前核对真实字节、尺寸和帧数；自定义 provider 若直接发布已解码图片，其分配预算由调用方负责，不能把本封装的检查当作拦截了外部分配。下载/来源读取在回调进入前由调用方限制，不承诺读取前的网络或插件内存上限。帧时长在第一轮逐帧核对，后续某帧超限时可能已经显示前面的帧，然后明确失败；不会静默停在首帧。只解码当前选择，不预解码整组，不清理其他调用方的全局缓存；本次 stream 使用独立的 cache key。

`resourceUsage` 提供当前真实 Flutter 解码器的字节/尺寸/帧数/已解码帧计数。它不是进程内存估算，不发额外通知或调度UI帧；调用方可采样。切图/重试/关闭清除本选择统计，背景状态保留真实计数供检测，不能以“忽略后台计数”证明停播。提高上限须自行取得相应设备证据。Android 实际资源量测与本轮状态将在收尾报告登记，未测上限不视为通过。

2026-10-13 接续进入宿主成果保存与 Android 构建/单台平台验证准备。宿主实现已保存至 `3287607cb30887f9df02d2b8dd1cd3fbf3a390cc` 并普通推送；Android 构建及待验状态以 [Android 交接](../../docs/design/image-viewer-android-report.md) 和 [单台清单](../../docs/design/image-viewer-android-checklist.md) 为准。示例使用独立 `component`/`nativecheck` Android flavor；正常查看版保持保存关闭，限定保存实验需两个开关同时满足。核心公共 API 不变，未接入主 App。

下文的封装交付段落保留 2026-10-12 宿主版本范围；当前平台结果与保存/设备验收不得从旧宿主结果推导。

版本仍为 `0.0.0`。本轮交付独立封装与宿主证据；Android/iOS 原生构建、真实权限、相册动画回放和真机交互待验，不能称双端完整通过。现行范围见 [本轮报告](../../docs/design/image-viewer-component-host-report.md)、[机器交接](../../docs/design/image-viewer-machine-handoff.md) 和 [完整计划](../../docs/design/image-viewer-component-plan.md)。M1 probe 和条件 GIF 实验继续保留为技术研究，不能代证正式组件验收。

## 公共入口

```dart
final controller = ViewerController(
  items: [
    ViewerItem(
      id: 'stable-media-id',
      semanticLabel: '图片说明',
      loadSource: () async => ViewerSource(
        provider: authorizedImageProvider,
        pixelSize: decodedPixelSize,
      ),
      // 可选：仅用户明确点击保存后调用；必须返回完整原始文件。
      resolveOriginal: () async => ViewerOriginal.bytes(
        completeOriginalBytes,
        ViewerOriginalFormat.webp,
      ),
      saveAllowed: false,
    ),
  ],
  initialIndex: 0,
);

// 放在调用方拥有的独立 route 内。
Scaffold(
  body: HnuImageViewer(
    controller: controller,
    onClosed: (reason) => Navigator.of(context).pop(reason),
    onChanged: (snapshot) { /* 只处理当前会话状态 */ },
  ),
);
```

`ViewerItem.provider(...)` 是已经拥有 ImageProvider 和解码尺寸时的便捷工厂。`ViewerSource` 复用 Flutter ImageProvider；缩放、平移、动画解码和退出渲染复用 extended_image/Flutter。组件需要宽高有界的视口。`ViewerController` 提供当前组、切图、手动重试、替换图片组、访问失效和关闭能力。调用方应使用不含 URL、私有路径或身份信息的媒体 ID。调用方拥有 controller 的创建和 dispose，并保留父页面滚动位置。Widget 不自行操作宿主 Navigator；关闭按钮、系统返回和合格下拉都通过一次关闭回调通知调用方。

## 输入与来源契约

- 组非空；初始索引有效；稳定 ID 非空、没有周围空白、组内唯一。生产模式也校验，不依赖 assert。同一 ID 必须代表同一内容版本；内容改变需新 ID。
- `pixelSize` 必须为有限正整数，并匹配 Flutter 解码输出。损坏图片、加载器异常和尺寸不一致反馈为脱敏错误类别，可关闭或手动重试。组件不把底层异常、URL、完整私有路径或原始图片放入回调/反馈。
- 只调用当前页的来源加载器，不提前读取/解码整组。加载器可能在切页、关闭、替换或失效后完成，组件按会话/选择/尝试代次丢弃旧结果。任意 Future 或底层读取能否真正取消由调用方来源实现负责。
- 受保护来源必须由调用方先授权，再提供加载器/provider。组件没有账号、Bearer、密码、恢复材料或认证 header 参数，不调用业务后端。调用方负责 provider 的授权、缓存 key 和缓存策略；不得把带长期私有磁盘缓存的 provider 当作组件自动安全缓存。组件不创建长期私有图片缓存，也不清空其他组件的全局缓存。
- 原始保存 resolver 必须返回完整原格式，查看 provider 可以是另一个符合尺寸契约的来源。禁止把缩略图或截图当作完整原图。路径来源由调用方保持可读、稳定且具有正确扩展名；组件不删除调用方文件。字节来源被复制为当前保存操作的快照。
- JPEG/PNG/WebP、GIF/动态 WebP 为目标格式；其他格式、EXIF完整矩阵、无限大媒体和手机资源上限尚未承诺。没有默认 GIF 转换、首帧降级、帧删减或质量降低。

## 会话、阅读与回调

普通图适屏居中，长图适宽从顶部进入。缩放基准随当前布局计算；回顶的同一次手势不产生退出变换或关闭，必须全部松手后再开始单指下拉。放大、双指和阅读方向锁定沿用 M1 验证过的适配规则。

本会话按稳定 ID 保存阅读锚点和相对基准缩放；返回已看图片恢复位置，布局变化按归一化锚点恢复。替换图片组开启新代次并清除原组的阅读状态；重试同内容保留当前锚点。真实系统旋转、触摸与手势组合仍需两端设备验证。

`invalidateAccess()` 是单向终态：停止显示、停止新的来源/保存、使当前操作 token 失效。关闭和 Widget 撤下也终结会话；重新打开请创建新 controller。一个 controller 只能同时绑定一个 viewer。`onChanged` 只描述仍绑定的当前会话，`onClosed` 只通知一次；Widget 撤下后不向新页面发布旧结果。调用方回调应快速完成，不在回调中抛异常。

祖先 TickerMode 用于路由隐藏；嵌入 Offstage 时调用方须同时设置 TickerMode(enabled: false)。当前可见图播放动画；切走、前后台生命周期、关闭和访问失效停止不可见播放。宿主可验证 Flutter 监听/帧调度；系统后台行为不能由宿主代证。

## 保存接口与原生门槛

`HnuImageViewer.enableAndroidSaving` 默认为 `true`。Android 未传入 `saveCoordinator` 时，Widget 创建并拥有一个使用 gal 的协调器；其他平台默认不创建，iOS 仍待平台验收。`enableAndroidSaving: false` 可关闭 Android 自动创建。调用方显式传入的 `saveCoordinator` 优先于此开关，仍由调用方负责 dispose，适用于自定义适配器或独立的平台实验：

```dart
final saver = ViewerSaveCoordinator(gallery: GalViewerGalleryWriter());
// HnuImageViewer(controller: controller, saveCoordinator: saver, ...)
// route 结束后 controller.dispose(); saver.dispose();
```

只查看不会请求权限、读取原文件或写入相册。即使 Android 默认启用，图片仍须有 `resolveOriginal`、`saveAllowed: true`、成功加载及有效前台会话，按钮才可用。自动创建的协调器在撤下 Widget、关闭自动入口或更换 controller 时失效/dispose；已交给系统的写入继续结算和清理，迟到结果不能改变新页面。调用方必须遵守 Android 最低 API29 的宿主构建基线。默认保存 PNG/JPEG/GIF/WebP 原文件，不转换、截帧或降质。

`ViewerGalleryWriter` 可以注入适配器；它的权限/写入 Future 必须如实结算，不能在系统仍读取文件时提前返回。`ViewerOriginal.bytes(bytes, format)` 或 `ViewerOriginal.file(path, format)` 支持 png/jpeg/gif/webp，JPEG 路径接受 jpg/jpeg。只在显式保存点击且业务许可有效时请求系统权限和完整来源，不因查看申请相册权限。

保存未结算时阻止连点。来源失败、权限拒绝、格式不支持、空间不足、临时文件失败、插件缺失和未知结果有不同反馈。`ViewerSaveResult` 包含脱敏状态、图片 ID、是否已调用保存适配器、是否仍为当前选择及清理状态；不自动重试未知写入。关闭/切图/撤销发生于写入前时停止新提交；调用保存适配器后不能承诺取消（gal 内部可能再次请求权限；组件无法介入其内部权限到写入过程）。旧操作可以结算，但 UI 不发布迟到成功或错误，也不影响新会话。

字节保存只创建独占临时目录，平台 Future 结算后才清理；调用方原路径不删除。清理失败不覆盖真实写入结果，忙态仍恢复，`retryCleanup()` 仅重试清理，绝不重写相册。注入临时目录 factory 时必须返回新建且完全归本操作所有的目录。

gal 2.3.3 的 iOS 文件导入存在强制解包的待核对风险。权限对话可能使应用进入 inactive 并令本次保存失效，需要两端核对首次授权、回到查看后再次主动保存的实际行为。原生导入成功、导出文件动画完整、Photos/目标相册实际播放分别验收。动态 WebP 兼容 GIF 仍为条件实验；只有原格式真实回放失败后，才评估具体质量/资源取舍，不默认转换。

## 示例与复验

`example/lib/component_example.dart` 展示当前封装：本地合成图片、当前页惰性加载、首次失败/手动重试、访问失效和调用方导航。保存实验默认关闭，专用平台验收才显式使用 `--dart-define=VIEWER_ENABLE_NATIVE_EXPORT=true`。旧 M1 场景保留为 `runM1Probe()` 与原设备测试入口。

保留两份 pubspec.lock。先使用已确认可独立写 bin/cache 的 SDK、独立 Pub/TEMP/日志目录；若不能确认不与认证冲突，不执行命令。实际复验入口和本轮结果/日志见机器交接与本轮报告：

```text
# packages/image_viewer
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --machine --concurrency=1
# packages/image_viewer/example
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter build bundle --debug --no-pub
```

锁定 Flutter 3.47.5 / Dart 3.13.4；extended_image 10.1.0、gal 2.3.3、path_provider 2.1.5。image 4.10.1 只用于 `tool/m1_animation_codec.dart` 实验，不导出产品转换 API。原 M1 36 项测试和新封装测试均保留，平台待验和业务 M4 接入单列。本轮不接主 App、不改认证/Go/SQL/上传/业务接口，不提交、推送、合并或部署。
