import 'package:flutter/material.dart';

import 'auth_wordmark_path.dart';

/// Fixed vector lettering so the brand does not depend on platform fonts.
class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '@SpeechFUL',
    image: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox.fromSize(
        size: authWordmarkSize,
        child: CustomPaint(
          painter: _WordmarkPainter(
            Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFFF2F4F7)
                : Colors.black,
          ),
        ),
      ),
    ),
  );
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawPath(authWordmarkPath, Paint()..color = color);

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) =>
      color != oldDelegate.color;
}
