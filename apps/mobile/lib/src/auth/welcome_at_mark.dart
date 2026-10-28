import 'package:flutter/material.dart';

/// Displays the shushing outline with the current theme's ink color.
class WelcomeAtMark extends StatelessWidget {
  const WelcomeAtMark({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 150,
    child: Center(
      child: Image.asset(
        'assets/branding/welcome-shush-mark.png',
        width: 126,
        height: 126,
        fit: BoxFit.contain,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}
