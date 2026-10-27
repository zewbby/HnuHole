import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import 'app_navigation.dart';

/// Home owns its reading intent; the root owns the single navigation surface.
/// This object carries no account data and is replaced with the authority window.
class FeedChromeController extends ChangeNotifier {
  bool _visible = true;
  bool _refreshing = false;
  Object? _owner;
  VoidCallback? _compose;
  String _tooltip = '写帖子';
  double _travel = 0;
  int _direction = 0;

  bool get visible => _visible;
  VoidCallback? get compose => _compose;
  String get tooltip => _tooltip;

  void bind(Object owner, VoidCallback compose, String tooltip) {
    final changed = _owner != owner || _tooltip != tooltip;
    _owner = owner;
    _compose = compose;
    _tooltip = tooltip;
    if (changed) notifyListeners();
  }

  void unbind(Object owner) {
    if (_owner != owner) return;
    _owner = _compose = null;
  }

  void show() {
    _travel = 0;
    _direction = 0;
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void refreshing(bool value) {
    _refreshing = value;
    if (value) show();
  }

  void beginDrag() {
    _travel = 0;
    _direction = 0;
  }

  void scroll(double delta, double pixels) {
    if (_refreshing || pixels <= 0) {
      show();
      return;
    }
    if (delta == 0) return;
    final direction = delta > 0 ? 1 : -1;
    if (_direction != direction) _travel = 0;
    _direction = direction;
    _travel += delta.abs();
    // Deliberate reading motion hides chrome; a shorter reverse reveals it.
    if (_travel < (direction > 0 ? 36 : 14)) return;
    final visible = direction < 0;
    if (_visible == visible) return;
    _visible = visible;
    notifyListeners();
  }
}

class FeedChromeScope extends InheritedWidget {
  const FeedChromeScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final FeedChromeController controller;

  static FeedChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedChromeScope>()?.controller;

  @override
  bool updateShouldNotify(FeedChromeScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Both ends use the same 240ms motion, without resizing the root's viewport.
class FeedChromeMotion extends StatelessWidget {
  const FeedChromeMotion({
    super.key,
    required this.visible,
    required this.builder,
    this.child,
  });
  final bool visible;
  final Widget Function(BuildContext, double, Widget?) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: visible ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    builder: builder,
    child: child,
  );
}

class FeedComposeButton extends StatelessWidget {
  const FeedComposeButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.floating = false,
  });
  final VoidCallback onPressed;
  final String tooltip;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return SizedBox(
      width: floating ? 60 : 52,
      height: floating ? 56 : 48,
      child: IconButton.filled(
        key: const ValueKey('feed-compose'),
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: floating ? p.action : p.background,
          foregroundColor: floating ? p.onAccent : p.ink,
          elevation: floating ? 2 : 0,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(floating ? 19 : 15),
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
}

class FeedNavigation extends StatelessWidget {
  const FeedNavigation({
    super.key,
    required this.controller,
    required this.selected,
    required this.onSelected,
    this.collapseSpace = false,
  });
  final FeedChromeController controller;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;
  final bool collapseSpace;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final home = selected == AppDestination.home;
      final visible = !home || controller.visible;
      return IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: FeedChromeMotion(
            visible: visible,
            builder: (context, progress, child) => collapseSpace
                ? ClipRect(
                    child: Align(
                      heightFactor: progress,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  )
                : FractionalTranslation(
                    translation: Offset(0, 1 - progress),
                    child: child,
                  ),
            child: HhAppNavigation(
              selected: selected,
              onSelected: onSelected,
              composeSlot: true,
              onCompose: visible ? controller.compose : null,
              composeTooltip: controller.tooltip,
            ),
          ),
        ),
      );
    },
  );
}
