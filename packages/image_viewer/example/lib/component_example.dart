import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

const _fixtures = [
  ('ordinary.png', Size(640, 480), ViewerOriginalFormat.png, '普通合成图片'),
  ('long.png', Size(480, 2400), ViewerOriginalFormat.png, '从顶部阅读的长图'),
  ('animation.gif', Size(96, 72), ViewerOriginalFormat.gif, 'GIF 动画'),
  ('animation.webp', Size(96, 72), ViewerOriginalFormat.webp, 'WebP 动画'),
];

// Test-only controls distinguish a short completed animation from a player
// that never starts. Original product fixtures and export bytes are unchanged.
const _galleryReplayFixtures = [
  ('animation.webp', Size(96, 72), ViewerOriginalFormat.webp, '短有限 WebP，0.8秒'),
  (
    'animation_replay_slow.webp',
    Size(96, 72),
    ViewerOriginalFormat.webp,
    '慢有限 WebP，12秒',
  ),
  (
    'animation_infinite.webp',
    Size(96, 72),
    ViewerOriginalFormat.webp,
    '无限 WebP',
  ),
  ('animation.gif', Size(96, 72), ViewerOriginalFormat.gif, '有限 GIF 对照'),
];

const _galleryIdentityFixtures = [
  (
    'replay_identity_slow.webp',
    Size(192, 144),
    ViewerOriginalFormat.webp,
    'SLOW 2s，有限两轮',
  ),
  (
    'replay_identity_fast.webp',
    Size(192, 144),
    ViewerOriginalFormat.webp,
    'FAST，无限循环',
  ),
];

final _androidFixtures = [
  for (var orientation = 1; orientation <= 8; orientation++)
    (
      'android_exif_$orientation.jpg',
      orientation >= 5 ? const Size(128, 192) : const Size(192, 128),
      ViewerOriginalFormat.jpeg,
      'EXIF 方向 $orientation',
    ),
  (
    'android_transparent.png',
    const Size(192, 128),
    ViewerOriginalFormat.png,
    '半透明图片',
  ),
  ('android_small.png', const Size(1, 1), ViewerOriginalFormat.png, '单像素图片'),
  ('android_wide.png', const Size(2400, 240), ViewerOriginalFormat.png, '宽图'),
  (
    'android_static_limit.png',
    const Size(3072, 4096),
    ViewerOriginalFormat.png,
    '静态像素上限',
  ),
  (
    'android_long_limit.png',
    const Size(480, 16384),
    ViewerOriginalFormat.png,
    '长图尺寸上限',
  ),
  (
    'android_animation_limit.webp',
    const Size(1024, 1024),
    ViewerOriginalFormat.webp,
    '动画像素上限',
  ),
  (
    'android_frames_limit.webp',
    const Size(128, 96),
    ViewerOriginalFormat.webp,
    '120帧动画',
  ),
  (
    'android_pixels_over.png',
    const Size(3073, 4096),
    ViewerOriginalFormat.png,
    '像素超限，预期拒绝',
  ),
  (
    'android_dimension_over.png',
    const Size(1, 16385),
    ViewerOriginalFormat.png,
    '尺寸超限，预期拒绝',
  ),
  (
    'android_frames_over.webp',
    const Size(128, 96),
    ViewerOriginalFormat.webp,
    '121帧，预期拒绝',
  ),
  (
    'android_duration_over.webp',
    const Size(128, 96),
    ViewerOriginalFormat.webp,
    '单帧时长超限，预期拒绝',
  ),
  (
    'android_gif_slow.gif',
    const Size(192, 128),
    ViewerOriginalFormat.gif,
    '每色一秒，GIF三轮',
  ),
  (
    'android_animation_work_over.webp',
    const Size(1024, 1024),
    ViewerOriginalFormat.webp,
    '动画总像素超限，预期拒绝',
  ),
  (
    'android_encoded_limit.png',
    const Size(640, 480),
    ViewerOriginalFormat.png,
    '编码16MiB上限',
  ),
  (
    'android_encoded_over.png',
    const Size(640, 480),
    ViewerOriginalFormat.png,
    '编码16MiB加一字节，预期拒绝',
  ),
];

enum ViewerFixtureSet {
  standard,
  galleryReplay,
  galleryIdentity,
  androidAcceptance,
}

const _androidDiagnostics = bool.fromEnvironment('VIEWER_ANDROID_DIAGNOSTICS');

// Android is enabled independently of the still-unverified iOS adapter.
bool get _nativeExportEnabled =>
    defaultTargetPlatform == TargetPlatform.android ||
    (const bool.fromEnvironment('VIEWER_ENABLE_NATIVE_EXPORT') &&
        appFlavor == 'nativecheck');
const _nativeExperimentsEnabled =
    _androidDiagnostics ||
    (bool.fromEnvironment('VIEWER_ENABLE_NATIVE_EXPORT') &&
        appFlavor == 'nativecheck');

enum NativeCheckSaveMode { normal, delayedAdapter, missingOwnedFile }

// Example-only fault injection around the real gal adapter. It does not prove
// system behavior until the nativecheck APK is executed on an authorized phone.
class _PlatformCheckGallery implements ViewerGalleryWriter {
  _PlatformCheckGallery(this.mode);
  final NativeCheckSaveMode mode;
  final _native = const GalViewerGalleryWriter();
  int _dispatches = 0;

  void _event(String stage, [Map<String, Object?> fields = const {}]) {
    debugPrint(
      'VIEWER_PLATFORM_EVENT ${jsonEncode({'stage': stage, 'mode': mode.name, ...fields})}',
    );
  }

  @override
  Future<bool> hasAccess() async {
    final granted = await _native.hasAccess();
    _event('nativeAccessChecked', {'granted': granted});
    return granted;
  }

  @override
  Future<bool> requestAccess() async {
    final granted = await _native.requestAccess();
    _event('nativePermissionResult', {'granted': granted});
    return granted;
  }

  @override
  Future<void> putImage(String originalPath) async {
    final operation = ++_dispatches;
    final ownedFile = File(originalPath);
    _event('adapterDispatched', {'operation': operation});
    if (mode == NativeCheckSaveMode.delayedAdapter) {
      // This is an injected adapter delay, not measured native write latency.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mode == NativeCheckSaveMode.missingOwnedFile) {
      // This example always resolves bytes; delete only its operation-owned file.
      if (!ownedFile.parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('hnuhole-image-viewer-')) {
        throw StateError('Expected example-owned temporary file.');
      }
      await ownedFile.delete();
      _event('ownedFileRemovedBeforeNativeCall', {'operation': operation});
    }
    try {
      _event('nativeWriteCalled', {'operation': operation});
      await _native.putImage(originalPath);
      _event('nativeWriteSucceeded', {'operation': operation});
    } catch (_) {
      _event('nativeWriteFailed', {'operation': operation});
      rethrow;
    } finally {
      // The coordinator cleans after this Future settles. Observe it without
      // publishing UI callbacks or logging private paths/raw plugin exceptions.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 500), () async {
          _event('settledCleanupObserved', {
            'operation': operation,
            'fileExists': await ownedFile.exists(),
            'directoryExists': await ownedFile.parent.exists(),
          });
        }),
      );
    }
  }
}

Future<Uint8List> _readFixture(String name) async {
  if (name == 'android_encoded_limit.png' ||
      name == 'android_encoded_over.png') {
    final over = name == 'android_encoded_over.png';
    final original = await _readFixture('ordinary.png');
    // Small legal ancillary PNG chunks before IEND fill the exact byte boundary.
    // CRCs are precomputed for the zero-filled payload; no large binary asset
    // or decoder/conversion implementation is introduced.
    final total = 16 * 1024 * 1024 + (over ? 1 : 0);
    final output = Uint8List(total);
    var at = original.length - 12;
    output.setRange(0, at, original);
    final data = ByteData.sublistView(output);
    for (var i = 0; i < 32; i++) {
      final payload = i < 31 ? 524288 : 520248 + (over ? 1 : 0);
      data.setUint32(at, payload);
      output.setRange(at + 4, at + 8, const [110, 112, 65, 100]); // npAd
      data.setUint32(
        at + 8 + payload,
        i < 31 ? 0x74bb768f : (over ? 0xf3a629b8 : 0x10328034),
      );
      at += payload + 12;
    }
    output.setRange(total - 12, total, original.sublist(original.length - 12));
    return output;
  }
  final data = await rootBundle.load('assets/fixtures/$name');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class ComponentApp extends StatelessWidget {
  const ComponentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HnuHole 独立图片组件',
    theme: ThemeData.dark(useMaterial3: true),
    home: const ComponentLauncher(),
  );
}

class ComponentLauncher extends StatelessWidget {
  const ComponentLauncher({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('独立图片组件')),
    body: ListView(
      children: [
        const ListTile(
          title: Text('普通图、长图、GIF 和动态 WebP'),
          subtitle: Text('仅使用本地合成图片。左右切换，长图回顶后松手再下拉关闭。'),
        ),
        for (var i = 0; i < _fixtures.length; i++)
          ListTile(
            title: Text(_fixtures[i].$1),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<ViewerCloseReason>(
                builder: (_) => ComponentScreen(initialIndex: i),
              ),
            ),
          ),
        ListTile(
          title: const Text('首次失败与手动重试'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<ViewerCloseReason>(
              builder: (_) =>
                  const ComponentScreen(initialIndex: 0, failOnce: true),
            ),
          ),
        ),
        ListTile(
          title: const Text('延迟加载与关闭隔离'),
          subtitle: const Text('合成来源延迟三秒；关闭后打开另一图片，旧结果不得影响新页面。'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<ViewerCloseReason>(
              builder: (_) => const ComponentScreen(
                initialIndex: 0,
                sourceDelay: Duration(seconds: 3),
              ),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('android-acceptance'),
          title: const Text('Android 格式与资源验收'),
          subtitle: const Text('合成方向、透明、大图、动图及超限失败场景。'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<ViewerCloseReason>(
              builder: (_) => const ComponentScreen(
                initialIndex: 0,
                fixtureSet: ViewerFixtureSet.androidAcceptance,
              ),
            ),
          ),
        ),
        if (_androidDiagnostics)
          ListTile(
            key: const ValueKey('android-auto-check'),
            title: const Text('自动核对 Android 素材与资源'),
            subtitle: const Text('仅本地素材；结束后显示结果，不操作相册。'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _AndroidAcceptanceRun(),
              ),
            ),
          ),
        if (_nativeExperimentsEnabled)
          ListTile(
            key: const ValueKey('gallery-replay-probe'),
            title: const Text('相册回放对照：短有限、慢有限、无限 WebP'),
            subtitle: const Text('仅实验素材；原文件保存不转换，播放器行为单独核对。'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<ViewerCloseReason>(
                builder: (_) => const ComponentScreen(
                  initialIndex: 0,
                  fixtureSet: ViewerFixtureSet.galleryReplay,
                ),
              ),
            ),
          ),
        if (_nativeExperimentsEnabled)
          ListTile(
            key: const ValueKey('gallery-identity-probe'),
            title: const Text('相册身份与时序对照：SLOW / FAST'),
            subtitle: const Text('画面标记区分文件身份；时序和循环仍按原文件保存。'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<ViewerCloseReason>(
                builder: (_) => const ComponentScreen(
                  initialIndex: 0,
                  fixtureSet: ViewerFixtureSet.galleryIdentity,
                ),
              ),
            ),
          ),
        if (_nativeExperimentsEnabled)
          for (final scenario in const [
            ('保存连点与关闭竞争（延迟适配器）', NativeCheckSaveMode.delayedAdapter),
            ('临时文件消失（真实 Gal 错误）', NativeCheckSaveMode.missingOwnedFile),
          ])
            ListTile(
              title: Text(scenario.$1),
              subtitle: const Text('限定合成素材故障注入；调用真实插件，结果另行核对。'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<ViewerCloseReason>(
                  builder: (_) =>
                      ComponentScreen(initialIndex: 2, saveMode: scenario.$2),
                ),
              ),
            ),
        ListTile(
          title: Text(_nativeExportEnabled ? '原文件保存已启用' : '此平台保存默认关闭'),
          subtitle: const Text('仅使用合成素材；原生权限、系统写入和相册回放分别验收。'),
        ),
      ],
    ),
  );
}

class _AndroidAcceptanceRun extends StatefulWidget {
  const _AndroidAcceptanceRun();
  @override
  State<_AndroidAcceptanceRun> createState() => _AndroidAcceptanceRunState();
}

class _AndroidAcceptanceRunState extends State<_AndroidAcceptanceRun> {
  late final ViewerController _controller;
  bool _running = true;
  int _passes = 0, _failures = 0;
  final _clock = Stopwatch();
  final List<FrameTiming> _timings = [];
  void _timing(List<FrameTiming> values) => _timings.addAll(values);
  void _event(String stage, Map<String, Object?> fields) => debugPrint(
    'VIEWER_ANDROID_SUITE ${jsonEncode({'stage': stage, ...fields})}',
  );

  @override
  void initState() {
    super.initState();
    _controller = ViewerController(
      items: [
        for (final fixture in _androidFixtures)
          ViewerItem(
            id: fixture.$1,
            semanticLabel: fixture.$4,
            loadSource: () async => ViewerSource(
              provider: MemoryImage(await _readFixture(fixture.$1)),
              pixelSize: fixture.$2,
            ),
          ),
      ],
    );
    WidgetsBinding.instance.addTimingsCallback(_timing);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final order = [
      ...List<int>.generate(_androidFixtures.length, (i) => i),
      for (var round = 0; round < 12; round++) ...[11, 0],
    ];
    _event('started', {
      'cases': order.length,
      'mode': 'actual Flutter Android decoder; no tester gesture injection',
    });
    for (final index in order) {
      if (!mounted || !_controller.active) return;
      _timings.clear();
      _clock.reset();
      _clock.start();
      _controller.select(index);
      while (mounted &&
          _controller.active &&
          _clock.elapsed < const Duration(seconds: 10) &&
          (_controller.status == ViewerLoadStatus.idle ||
              _controller.status == ViewerLoadStatus.loading)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (!mounted || !_controller.active) return;
      final readyMs = _clock.elapsedMilliseconds;
      final fixture = _androidFixtures[index];
      final rejected = fixture.$1.contains('_over.');
      final pass = rejected
          ? _controller.failure == ViewerFailure.resourceLimit
          : _controller.status == ViewerLoadStatus.ready;
      if (pass) {
        _passes++;
      } else {
        _failures++;
      }
      await Future<void>.delayed(
        Duration(milliseconds: index == 11 || index == 12 ? 1200 : 300),
      );
      if (!mounted || !_controller.active) return;
      final usage = _controller.resourceUsage;
      _event('case', {
        'item': fixture.$1,
        'result': pass ? 'PASS' : 'FAIL',
        'expectedReject': rejected,
        'status': _controller.status.name,
        'failure': _controller.failure?.name,
        'readyMs': readyMs,
        'encodedBytes': usage?.encodedBytes,
        'width': usage?.width,
        'height': usage?.height,
        'frameCount': usage?.frameCount,
        'decodedFrames': usage?.decodedFrames,
        'renderedFrames': _timings.length,
        'maxBuildUs': _timings.isEmpty
            ? null
            : _timings
                  .map((v) => v.buildDuration.inMicroseconds)
                  .reduce((a, b) => a > b ? a : b),
        'maxRasterUs': _timings.isEmpty
            ? null
            : _timings
                  .map((v) => v.rasterDuration.inMicroseconds)
                  .reduce((a, b) => a > b ? a : b),
      });
    }
    if (mounted) {
      setState(() => _running = false);
      _event('finished', {
        'passed': _passes,
        'failed': _failures,
        'cases': order.length,
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_timing);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_running ? '正在核对合成素材' : '核对完成：$_passes 通过 / $_failures 失败'),
    ),
    body: HnuImageViewer(
      controller: _controller,
      onClosed: (_) => Navigator.of(context).pop(),
    ),
  );
}

class ComponentScreen extends StatefulWidget {
  const ComponentScreen({
    required this.initialIndex,
    this.failOnce = false,
    this.sourceDelay = Duration.zero,
    this.saveMode = NativeCheckSaveMode.normal,
    this.fixtureSet = ViewerFixtureSet.standard,
    super.key,
  });
  final int initialIndex;
  final bool failOnce;
  final Duration sourceDelay;
  final NativeCheckSaveMode saveMode;
  final ViewerFixtureSet fixtureSet;

  @override
  State<ComponentScreen> createState() => _ComponentScreenState();
}

class _ComponentScreenState extends State<ComponentScreen>
    with WidgetsBindingObserver {
  late final ViewerController _controller;
  ViewerSaveCoordinator? _saver;
  bool _firstAttempt = true;
  bool _hidden = false;
  Timer? _samples;
  Timer? _restoreVisible;
  final _elapsed = Stopwatch();

  void _event(String stage) {
    if (!_androidDiagnostics) return;
    final usage = _controller.resourceUsage;
    final reading = _controller.readingPosition(_controller.currentItem.id);
    debugPrint(
      'VIEWER_ANDROID_EVENT ${jsonEncode({'stage': stage, 'item': _controller.currentItem.id, 'elapsedMs': _elapsed.elapsedMilliseconds, 'active': _controller.active, 'foreground': _controller.foreground, 'status': _controller.status.name, 'failure': _controller.failure?.name, 'hidden': _hidden, 'encodedBytes': usage?.encodedBytes, 'width': usage?.width, 'height': usage?.height, 'frameCount': usage?.frameCount, 'decodedFrames': usage?.decodedFrames, 'zoom': reading?.zoomFactor, 'anchorX': reading?.normalizedAnchor.dx, 'anchorY': reading?.normalizedAnchor.dy})}',
    );
  }

  @override
  void initState() {
    super.initState();
    final fixtures = switch (widget.fixtureSet) {
      ViewerFixtureSet.standard => _fixtures,
      ViewerFixtureSet.galleryReplay => _galleryReplayFixtures,
      ViewerFixtureSet.galleryIdentity => _galleryIdentityFixtures,
      ViewerFixtureSet.androidAcceptance => _androidFixtures,
    };
    _controller = ViewerController(
      initialIndex: widget.initialIndex,
      items: [
        for (final fixture in fixtures)
          ViewerItem(
            id: fixture.$1,
            semanticLabel: fixture.$4,
            loadSource: () async {
              if (widget.sourceDelay != Duration.zero) {
                await Future<void>.delayed(widget.sourceDelay);
              }
              if (widget.failOnce && _firstAttempt) {
                _firstAttempt = false;
                throw StateError('Synthetic source failure');
              }
              return ViewerSource(
                provider: MemoryImage(await _readFixture(fixture.$1)),
                pixelSize: fixture.$2,
              );
            },
            resolveOriginal: () async => ViewerOriginal.bytes(
              await _readFixture(fixture.$1),
              fixture.$3,
            ),
          ),
      ],
    );
    _elapsed.start();
    if (_androidDiagnostics) {
      WidgetsBinding.instance.addObserver(this);
      _samples = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _event('sample'),
      );
    }
    // Android default saving uses the real adapter. Fault injection is confined
    // to the explicit diagnostic entry points; it never changes original bytes.
    if (_nativeExportEnabled) {
      _saver = ViewerSaveCoordinator(
        gallery: _nativeExperimentsEnabled
            ? _PlatformCheckGallery(widget.saveMode)
            : const GalViewerGalleryWriter(),
      );
    }
  }

  @override
  void dispose() {
    _event('dispose');
    WidgetsBinding.instance.removeObserver(this);
    _samples?.cancel();
    _restoreVisible?.cancel();
    _controller.dispose();
    _saver?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _event('lifecycle:${state.name}');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(switch (widget.fixtureSet) {
        ViewerFixtureSet.standard => '来源控制示例',
        ViewerFixtureSet.galleryReplay => '相册回放对照',
        ViewerFixtureSet.galleryIdentity => '相册身份与时序对照',
        ViewerFixtureSet.androidAcceptance => 'Android 格式与资源验收',
      }),
      actions: [
        IconButton(
          tooltip: '临时隐藏四秒',
          icon: const Icon(Icons.visibility_off),
          onPressed: () {
            _restoreVisible?.cancel();
            setState(() => _hidden = true);
            _restoreVisible = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() => _hidden = false);
            });
          },
        ),
        IconButton(
          tooltip: '模拟访问失效',
          onPressed: _controller.invalidateAccess,
          icon: const Icon(Icons.block),
        ),
      ],
    ),
    body: TickerMode(
      enabled: !_hidden,
      child: Offstage(
        offstage: _hidden,
        child: HnuImageViewer(
          controller: _controller,
          saveCoordinator: _saver,
          onChanged: (_) => _event('changed'),
          onClosed: (reason) => Navigator.of(context).pop(reason),
        ),
      ),
    ),
  );
}
