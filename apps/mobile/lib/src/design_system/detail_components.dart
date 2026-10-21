import 'package:flutter/material.dart';

import '../posts/x_feed.dart';

/// Vector contours shared by the accepted preview and real detail screen.
const detailIconInk = Color(0xFF59666D);

TextStyle detailType(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.45,
}) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
);

class DetailAvatar extends StatelessWidget {
  const DetailAvatar({super.key, required this.name, this.radius = 24});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF18ADBA), Color(0xFF83A95B), Color(0xFF639CC2)];
    final hash = name.runes.fold<int>(0, (a, b) => a + b);
    final color = colors[hash % colors.length];
    return ExcludeSemantics(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.white, .13)!,
              Color.lerp(color, Colors.black, .07)!,
            ],
          ),
        ),
        child: Text(
          name.characters.firstOrNull ?? '海',
          style: detailType(
            context,
            radius * .85,
            weight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class DetailAction extends StatelessWidget {
  const DetailAction({
    super.key,
    this.buttonKey,
    required this.action,
    required this.label,
    this.count,
    this.selected = false,
    this.onPressed,
    this.size = 24,
  });
  final Key? buttonKey;
  final FeedAction action;
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback? onPressed;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = selected
        ? (action == FeedAction.like
              ? const Color(0xFFCC2929)
              : Theme.of(context).colorScheme.primary)
        : (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFA1B2C2)
              : detailIconInk);
    return Semantics(
      label: count == null ? label : '$label，$count',
      button: true,
      toggled: action == FeedAction.like || action == FeedAction.bookmark
          ? selected
          : null,
      child: TextButton(
        key: buttonKey,
        style:
            TextButton.styleFrom(
              foregroundColor: color,
              disabledForegroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(48, 48),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: DetailGlyph(action, color, selected),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 7),
                Text(
                  count!,
                  style: detailType(context, size < 24 ? 12 : 14, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DetailGlyph extends CustomPainter {
  const DetailGlyph(this.action, this.color, this.selected);
  final FeedAction action;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (action) {
      case FeedAction.comment:
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..cubicTo(6.3, 3, 2.5, 6.5, 2.5, 11.1)
            ..cubicTo(2.5, 14.4, 4.5, 17, 7.8, 18.1)
            ..lineTo(7.8, 21)
            ..lineTo(12.1, 18.8)
            ..cubicTo(17.8, 18.8, 21.5, 15.6, 21.5, 11.1)
            ..cubicTo(21.5, 6.5, 17.7, 3, 12, 3)
            ..close(),
          pen,
        );
      case FeedAction.like:
        final heart = Path()
          ..moveTo(12, 20.5)
          ..cubicTo(9.6, 18.7, 3, 13.65, 3, 8.65)
          ..cubicTo(3, 3.7, 8.65, 2.65, 12, 6.3)
          ..cubicTo(15.35, 2.65, 21, 3.7, 21, 8.65)
          ..cubicTo(21, 13.65, 14.4, 18.7, 12, 20.5)
          ..close();
        if (selected) canvas.drawPath(heart, Paint()..color = color);
        canvas.drawPath(heart, pen);
      case FeedAction.bookmark:
        final bookmark = Path()
          ..moveTo(6, 3.3)
          ..lineTo(18, 3.3)
          ..quadraticBezierTo(20, 3.3, 20, 5.3)
          ..lineTo(20, 21.2)
          ..lineTo(12, 16.3)
          ..lineTo(4, 21.2)
          ..lineTo(4, 5.3)
          ..quadraticBezierTo(4, 3.3, 6, 3.3)
          ..close();
        if (selected) canvas.drawPath(bookmark, Paint()..color = color);
        canvas.drawPath(bookmark, pen);
      case FeedAction.share:
        canvas.drawLine(
          const Offset(7.51, 10.88),
          const Offset(16.09, 6.12),
          pen,
        );
        canvas.drawLine(
          const Offset(7.51, 13.12),
          const Offset(16.09, 17.88),
          pen,
        );
        for (final center in [
          const Offset(5.5, 12),
          const Offset(18.1, 5),
          const Offset(18.1, 19),
        ]) {
          canvas.drawCircle(center, 2.3, pen);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetailGlyph oldDelegate) =>
      oldDelegate.action != action ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}

enum DetailChrome { back, more, image, expand }

class DetailChromeIcon extends StatelessWidget {
  const DetailChromeIcon(
    this.icon, {
    super.key,
    required this.color,
    required this.size,
  });
  final DetailChrome icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: DetailChromePainter(icon, color)),
  );
}

class DetailChromePainter extends CustomPainter {
  const DetailChromePainter(this.icon, this.color);
  final DetailChrome icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (icon) {
      case DetailChrome.back:
        pen.strokeWidth = 2.1;
        canvas.drawPath(
          Path()
            ..moveTo(11, 4.5)
            ..lineTo(3.5, 12)
            ..lineTo(11, 19.5)
            ..moveTo(3.8, 12)
            ..lineTo(21, 12),
          pen,
        );
      case DetailChrome.more:
        for (final y in [5.5, 12.0, 18.5]) {
          canvas.drawCircle(Offset(12, y), 1.45, Paint()..color = color);
        }
      case DetailChrome.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 3, 18, 18),
            const Radius.circular(3.4),
          ),
          pen,
        );
        canvas.drawCircle(const Offset(15.8, 8.2), 1.4, Paint()..color = color);
        canvas.drawPath(
          Path()
            ..moveTo(3.7, 17.2)
            ..lineTo(8.1, 12.1)
            ..quadraticBezierTo(8.7, 11.4, 9.3, 12.1)
            ..lineTo(13.5, 16.8)
            ..lineTo(15.4, 14.7)
            ..quadraticBezierTo(15.9, 14.1, 16.4, 14.7)
            ..lineTo(20.4, 19.1),
          pen,
        );
      case DetailChrome.expand:
        canvas.drawPath(
          Path()
            ..moveTo(14.1, 3.9)
            ..lineTo(20.1, 3.9)
            ..lineTo(20.1, 9.9)
            ..moveTo(19.7, 4.3)
            ..lineTo(13.7, 10.3)
            ..moveTo(9.9, 20.1)
            ..lineTo(3.9, 20.1)
            ..lineTo(3.9, 14.1)
            ..moveTo(4.3, 19.7)
            ..lineTo(10.3, 13.7),
          pen,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetailChromePainter old) =>
      icon != old.icon || color != old.color;
}
