import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import 'feed_chrome.dart';

enum AppDestination { home, messages, directMessages, personal }

/// Shared fixed root navigation. Notification and private-message destinations
/// are independent; unread/receipt state is never changed by this widget.
class HhAppNavigation extends StatelessWidget {
  const HhAppNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    this.composeSlot = false,
    this.onCompose,
    this.composeTooltip = '写帖子',
  });
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final bool composeSlot;
  final VoidCallback? onCompose;
  final String composeTooltip;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line, width: .5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final destination in AppDestination.values) ...[
                if (composeSlot && destination == AppDestination.directMessages)
                  Expanded(
                    child: Center(
                      child: onCompose == null
                          ? const SizedBox(width: 52, height: 48)
                          : FeedComposeButton(
                              onPressed: onCompose!,
                              tooltip: composeTooltip,
                            ),
                    ),
                  ),
                Expanded(
                  child: Semantics(
                    selected: selected == destination,
                    child: IconButton(
                      key: ValueKey('destination:${destination.name}'),
                      tooltip: switch (destination) {
                        AppDestination.home => '首页',
                        AppDestination.messages => '消息',
                        AppDestination.directMessages => '私信',
                        AppDestination.personal => '我的',
                      },
                      onPressed: () {
                        if (selected != destination) onSelected(destination);
                      },
                      icon: CustomPaint(
                        size: const Size(27, 27),
                        painter: HhNavigationGlyph(
                          destination,
                          selected == destination ? p.action : p.ink,
                          selected == destination,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Code-native vectors matching the supplied bell and single speech bubble.
class HhNavigationGlyph extends CustomPainter {
  const HhNavigationGlyph(this.destination, this.color, this.selected);
  final AppDestination destination;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void shape(Path path) {
      if (selected) canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, pen);
    }

    switch (destination) {
      case AppDestination.home:
        shape(
          Path()
            ..moveTo(3, 12)
            ..lineTo(14, 3)
            ..lineTo(25, 12)
            ..lineTo(25, 24)
            ..quadraticBezierTo(25, 25, 24, 25)
            ..lineTo(17, 25)
            ..lineTo(17, 17)
            ..lineTo(11, 17)
            ..lineTo(11, 25)
            ..lineTo(4, 25)
            ..quadraticBezierTo(3, 25, 3, 24)
            ..close(),
        );
      case AppDestination.messages:
        shape(
          Path()
            ..moveTo(4, 21)
            ..cubicTo(5.7, 17.6, 5.5, 13.1, 6.4, 9.3)
            ..cubicTo(7.2, 5.7, 9.9, 3.4, 14, 3.4)
            ..cubicTo(18.1, 3.4, 20.8, 5.7, 21.6, 9.3)
            ..cubicTo(22.5, 13.1, 22.3, 17.6, 24, 21)
            ..close(),
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.4, 24)
            ..quadraticBezierTo(14, 28, 17.6, 24),
          pen,
        );
      case AppDestination.directMessages:
        shape(
          Path()
            ..moveTo(14, 3)
            ..cubicTo(7.4, 3, 3, 7.1, 3, 12.7)
            ..cubicTo(3, 16, 4.3, 18.7, 6.7, 20.5)
            ..lineTo(4.6, 25)
            ..lineTo(11.2, 22.4)
            ..cubicTo(18.9, 24.1, 25, 19.5, 25, 12.7)
            ..cubicTo(25, 7.1, 20.5, 3, 14, 3)
            ..close(),
        );
      case AppDestination.personal:
        final paint = selected ? (Paint()..color = color) : pen;
        canvas.drawCircle(const Offset(14, 8.5), 4.5, paint);
        shape(
          Path()
            ..moveTo(4, 25)
            ..lineTo(4, 23)
            ..cubicTo(4, 18.5, 8.2, 16.7, 14, 16.7)
            ..cubicTo(19.8, 16.7, 24, 18.5, 24, 23)
            ..lineTo(24, 25)
            ..close(),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HhNavigationGlyph oldDelegate) =>
      destination != oldDelegate.destination ||
      color != oldDelegate.color ||
      selected != oldDelegate.selected;
}
