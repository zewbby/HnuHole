import 'package:flutter/material.dart';

import '../auth/auth_presentation.dart';
import '../posts/feed_screen.dart';
import 'channel_directory_controller.dart';

/// Login and authoritative directory loading only. The app root presents the
/// recommended feed once the complete directory and session are available.
class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    required this.directory,
    required this.onLoginRequested,
    this.restoringSession = false,
    this.onMessagesPressed,
    this.messagesUnread = false,
  });

  final ChannelDirectoryController directory;
  final VoidCallback onLoginRequested;
  final bool restoringSession;
  final VoidCallback? onMessagesPressed;
  final bool messagesUnread;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  bool _shown = false, _queued = false, _retrying = false;
  DialogRoute<bool>? _dialog;

  @override
  void initState() {
    super.initState();
    widget.directory.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      oldWidget.directory.removeListener(_changed);
      widget.directory.addListener(_changed);
      _shown = false;
    }
    _changed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _changed();
  }

  void _changed() {
    if (!mounted) return;
    final failed =
        !widget.restoringSession &&
        widget.directory.status == ChannelDirectoryStatus.failure;
    if (!failed && !_retrying) _shown = false;
    if (failed && !_shown && !_queued && !_retrying) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _queued = false;
        if (!mounted ||
            widget.restoringSession ||
            widget.directory.status != ChannelDirectoryStatus.failure ||
            _shown ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        _shown = true;
        final route = DialogRoute<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            key: const ValueKey('entry-unavailable-dialog'),
            title: const Text('暂时无法进入'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('重试'),
              ),
            ],
          ),
        );
        _dialog = route;
        final retry = await Navigator.of(context).push(route);
        if (_dialog == route) _dialog = null;
        if (!mounted || retry != true) return;
        setState(() => _retrying = true);
        try {
          await widget.directory.retry();
        } finally {
          if (mounted) {
            setState(() {
              _retrying = false;
              _shown = false;
            });
            _changed();
          }
        }
      });
    }
    final route = _dialog;
    if (!failed && !_retrying && route?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
    }
  }

  @override
  void dispose() {
    widget.directory.removeListener(_changed);
    final route = _dialog;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.directory,
    builder: (context, _) => _retrying
        ? AuthWelcomeScreen(onStarted: widget.onLoginRequested)
        : widget.restoringSession ||
              widget.directory.status == ChannelDirectoryStatus.loading
        ? const FeedStartupScreen()
        : widget.directory.status == ChannelDirectoryStatus.ready
        ? const FeedStartupScreen()
        : AuthWelcomeScreen(onStarted: widget.onLoginRequested),
  );
}
