import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../channels/channel.dart';

/// In-memory viewport state. It intentionally has no persistence adapter: a
/// new instance is created on app restart or after a fresh login.
class ChannelTreeSession {
  Matrix4? _transform;

  Matrix4? get transform {
    final value = _transform;
    return value == null ? null : Matrix4.copy(value);
  }

  void remember(Matrix4 transform) {
    _transform = Matrix4.copy(transform);
  }

  void clear() {
    _transform = null;
  }
}

/// Computes an adaptive 2D scene. The first five nodes stay around the
/// initial viewport; the two remaining nodes are deliberately deeper in the
/// scene and become reachable by dragging.
class ChannelTreeLayout {
  const ChannelTreeLayout._();

  static const double nodeRadius = 38;

  static Map<String, Offset> positions({
    required List<Channel> channels,
    required Size viewport,
    required Size scene,
  }) {
    final center = Offset(viewport.width * 0.5, viewport.height * 0.5);
    final base = <String, Offset>{
      'vent': center + Offset(-viewport.width * 0.26, -viewport.height * 0.18),
      'warning': center + Offset(viewport.width * 0.03, -viewport.height * 0.29),
      'recommendation': center + Offset(viewport.width * 0.27, -viewport.height * 0.04),
      'buddy': center + Offset(-viewport.width * 0.16, viewport.height * 0.23),
      'emotion': center + Offset(viewport.width * 0.20, viewport.height * 0.22),
      // The exploratory nodes are inside the scene but outside the initial
      // viewport. Dragging right/down reveals them without another request.
      'mutual_help': Offset(viewport.width * 1.72, viewport.height * 1.12),
      'technology': Offset(viewport.width * 1.12, viewport.height * 1.76),
    };

    final result = <String, Offset>{};
    for (final channel in channels) {
      final candidate = base[channel.code] ??
          Offset(scene.width * 0.5, scene.height * 0.5);
      result[channel.code] = Offset(
        _clamp(candidate.dx, nodeRadius, scene.width - nodeRadius),
        _clamp(candidate.dy, nodeRadius, scene.height - nodeRadius),
      );
    }
    return result;
  }

  static double _clamp(double value, double minimum, double maximum) {
    if (value < minimum) {
      return minimum;
    }
    if (value > maximum) {
      return maximum;
    }
    return value;
  }

  static Size sceneSize(Size viewport) {
    return Size(
      math.max(viewport.width * 2.5, 900).toDouble(),
      math.max(viewport.height * 2.5, 900).toDouble(),
    );
  }
}

class ChannelTree extends StatefulWidget {
  const ChannelTree({
    super.key,
    required this.channels,
    required this.session,
    required this.onChannelSelected,
  });

  final List<Channel> channels;
  final ChannelTreeSession session;
  final ValueChanged<Channel> onChannelSelected;

  @override
  State<ChannelTree> createState() => _ChannelTreeState();
}

class _ChannelTreeState extends State<ChannelTree> {
  late final TransformationController _transformationController;
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController(
      widget.session.transform ?? Matrix4.identity(),
    );
  }

  @override
  void didUpdateWidget(covariant ChannelTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _transformationController.value =
          widget.session.transform ?? Matrix4.identity();
    }
    final oldCodes = oldWidget.channels.map((channel) => channel.code).join('|');
    final newCodes = widget.channels.map((channel) => channel.code).join('|');
    if (oldCodes != newCodes) {
      _selectedCode = null;
      if (widget.session.transform == null) {
        _transformationController.value = Matrix4.identity();
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 560,
        );
        final scene = ChannelTreeLayout.sceneSize(viewport);
        final positions = ChannelTreeLayout.positions(
          channels: widget.channels,
          viewport: viewport,
          scene: scene,
        );
        final nodes = widget.channels
            .map((channel) => _buildNode(context, channel, positions[channel.code]!))
            .toList(growable: false);

        return ClipRect(
          child: InteractiveViewer(
            constrained: false,
            transformationController: _transformationController,
            minScale: 0.62,
            maxScale: 2.25,
            boundaryMargin: EdgeInsets.all(
              math.max(viewport.width, viewport.height).toDouble(),
            ),
            onInteractionEnd: (_) {
              widget.session.remember(_transformationController.value);
            },
            child: SizedBox(
              width: scene.width,
              height: scene.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreeBranchesPainter(positions: positions),
                    ),
                  ),
                  ...nodes,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNode(BuildContext context, Channel channel, Offset center) {
    final selected = _selectedCode == channel.code;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = channel.initiallyVisible
        ? colorScheme.primary
        : colorScheme.tertiary;
    return Positioned(
      left: center.dx - ChannelTreeLayout.nodeRadius,
      top: center.dy - ChannelTreeLayout.nodeRadius,
      width: ChannelTreeLayout.nodeRadius * 2,
      height: ChannelTreeLayout.nodeRadius * 2,
      child: Semantics(
        button: true,
        label: channel.displayName,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _selectedCode = channel.code;
            });
            widget.onChannelSelected(channel);
          },
          child: AnimatedScale(
            scale: selected ? 1.16 : 1,
            duration: const Duration(milliseconds: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : colorScheme.surface,
                border: Border.all(
                  color: accent,
                  width: selected ? 4 : 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: selected ? 0.42 : 0.2),
                    blurRadius: selected ? 18 : 10,
                    spreadRadius: selected ? 2 : 0,
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      channel.displayName,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeBranchesPainter extends CustomPainter {
  const _TreeBranchesPainter({required this.positions});

  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final paint = Paint()
      ..color = const Color(0x466E90A8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final position in positions.values) {
      canvas.drawLine(center, position, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TreeBranchesPainter oldDelegate) {
    return oldDelegate.positions != positions;
  }
}
