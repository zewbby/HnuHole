import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

const fixtureNames = [
  'ordinary.png',
  'long.png',
  'animation.gif',
  'animation.webp',
];
const fixtureSizes = [
  Size(640, 480),
  Size(480, 2400),
  Size(96, 72),
  Size(96, 72),
];
void main() => runApp(const M1App());

class M1App extends StatelessWidget {
  const M1App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HnuHole 图片 M1 验证',
    theme: ThemeData.dark(useMaterial3: true),
    home: const ProbeLauncher(),
  );
}

class ProbeLauncher extends StatefulWidget {
  const ProbeLauncher({super.key});
  @override
  State<ProbeLauncher> createState() => _ProbeLauncherState();
}

class _ProbeLauncherState extends State<ProbeLauncher> {
  Future<void> _open(int start) async {
    final data = <Uint8List>[];
    for (final name in fixtureNames) {
      data.add(
        (await rootBundle.load('assets/fixtures/$name')).buffer.asUint8List(),
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProbeScreen(data: data, start: start),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('图片查看 M1 技术验证')),
    body: ListView(
      children: [
        const ListTile(title: Text('独立场景图片；不连接社区或账号。')),
        for (var i = 0; i < fixtureNames.length; i++)
          ListTile(title: Text(fixtureNames[i]), onTap: () => _open(i)),
        const ListTile(title: Text('打开系统相册检查回放'), onTap: Gal.open),
      ],
    ),
  );
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({required this.data, required this.start, super.key});
  final List<Uint8List> data;
  final int start;
  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  final viewer = GlobalKey<M1ViewerProbeState>();
  final metrics = ProbeMetrics();
  final saver = M1SaveProbe();
  late final List<ProbeImage> images;
  bool active = true;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    images = List.generate(
      widget.data.length,
      (i) => ProbeImage(
        fixtureNames[i],
        MemoryImage(widget.data[i]),
        fixtureSizes[i],
      ),
    );
  }

  @override
  void dispose() {
    saver.invalidate();
    super.dispose();
  }

  Future<void> _save() async {
    final index = viewer.currentState?.index ?? widget.start;
    setState(() => saving = true);
    final result = await saver.save(
      widget.data[index],
      fixtureNames[index].split('.').last,
    );
    if (mounted && active) {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'written' ? '系统写入完成，请到相册检查动画回放' : '保存结果：$result',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('图片验证'),
      actions: [
        IconButton(
          tooltip: '保存当前原图',
          onPressed: active && !saving ? _save : null,
          icon: const Icon(Icons.download),
        ),
        IconButton(
          tooltip: '模拟访问失效',
          onPressed: () {
            saver.invalidate();
            setState(() => active = false);
          },
          icon: const Icon(Icons.block),
        ),
      ],
    ),
    body: M1ViewerProbe(
      key: viewer,
      images: images,
      metrics: metrics,
      initialIndex: widget.start,
      active: active,
    ),
  );
}
