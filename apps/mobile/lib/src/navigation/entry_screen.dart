import 'package:flutter/material.dart';

import '../channels/channel.dart';
import 'channel_directory_controller.dart';
import 'channel_tree.dart';

/// The entry surface deliberately keeps authentication outside the tree. The
/// host app calls [onLoginRequested], then passes the authenticated session token
/// to [ChannelDirectoryController.setSessionToken].
class EntryScreen extends StatefulWidget {
  EntryScreen({
    super.key,
    required this.directory,
    required this.onLoginRequested,
    required this.onChannelSelected,
    ChannelTreeSession? treeSession,
    this.onMessagesPressed,
    this.onProfilePressed,
  }) : treeSession = treeSession ?? ChannelTreeSession();

  final ChannelDirectoryController directory;
  final VoidCallback onLoginRequested;
  final ValueChanged<Channel> onChannelSelected;
  final ChannelTreeSession treeSession;
  final VoidCallback? onMessagesPressed;
  final VoidCallback? onProfilePressed;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  @override
  void initState() {
    super.initState();
    widget.directory.addListener(_onDirectoryChanged);
  }

  @override
  void didUpdateWidget(covariant EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      oldWidget.directory.removeListener(_onDirectoryChanged);
      widget.directory.addListener(_onDirectoryChanged);
    }
  }

  @override
  void dispose() {
    widget.directory.removeListener(_onDirectoryChanged);
    super.dispose();
  }

  void _onDirectoryChanged() {
    if (!mounted) {
      return;
    }
    if (widget.directory.status == ChannelDirectoryStatus.signedOut) {
      // Position is session-only. Signing out or losing a session must reset
      // it so a later login starts at the fixed initial layout.
      widget.treeSession.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.directory.status;
    final showTree = state == ChannelDirectoryStatus.ready;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _EntryHeader(
              authenticated: widget.directory.isAuthenticated,
              onMessagesPressed: widget.onMessagesPressed,
              onProfilePressed: widget.onProfilePressed,
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _TreeShell(
                      onEntryTap: state == ChannelDirectoryStatus.signedOut
                          ? widget.onLoginRequested
                          : null,
                      child: showTree
                          ? ChannelTree(
                              channels: widget.directory.channels,
                              session: widget.treeSession,
                              onChannelSelected: widget.onChannelSelected,
                            )
                          : const SizedBox.expand(),
                    ),
                  ),
                  if (!showTree)
                    _StatusOverlay(
                      state: state,
                      directory: widget.directory,
                      onLoginRequested: widget.onLoginRequested,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryHeader extends StatelessWidget {
  const _EntryHeader({
    required this.authenticated,
    this.onMessagesPressed,
    this.onProfilePressed,
  });

  final bool authenticated;
  final VoidCallback? onMessagesPressed;
  final VoidCallback? onProfilePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'S.A.Y',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  'W.H.A.T',
                  style: TextStyle(fontSize: 12, letterSpacing: 1.4),
                ),
              ],
            ),
          ),
          if (authenticated && onMessagesPressed != null)
            IconButton(
              tooltip: 'Messages',
              onPressed: onMessagesPressed,
              icon: const Icon(Icons.forum_outlined),
            ),
          if (authenticated && onProfilePressed != null)
            IconButton(
              tooltip: 'My content',
              onPressed: onProfilePressed,
              icon: const Icon(Icons.person_outline),
            ),
        ],
      ),
    );
  }
}

class _TreeShell extends StatelessWidget {
  const _TreeShell({required this.child, this.onEntryTap});

  final Widget child;
  final VoidCallback? onEntryTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.symmetric(
          horizontal: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.14),
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const CustomPaint(painter: _EmptyTreePainter()),
          child,
          if (onEntryTap != null)
            Center(
              child: Semantics(
                button: true,
                label: '登录或注册，进入树洞',
                child: GestureDetector(
                  onTap: onEntryTap,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.login_rounded),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyTreePainter extends CustomPainter {
  const _EmptyTreePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.5, size.height * 0.76);
    final paint = Paint()
      ..color = const Color(0x446E90A8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final trunkTop = Offset(size.width * 0.5, size.height * 0.42);
    canvas.drawLine(origin, trunkTop, paint);
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.56),
      Offset(size.width * 0.28, size.height * 0.28),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.52),
      Offset(size.width * 0.72, size.height * 0.22),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.62),
      Offset(size.width * 0.18, size.height * 0.52),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.62),
      Offset(size.width * 0.82, size.height * 0.48),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyTreePainter oldDelegate) => false;
}

class _StatusOverlay extends StatelessWidget {
  const _StatusOverlay({
    required this.state,
    required this.directory,
    required this.onLoginRequested,
  });

  final ChannelDirectoryStatus state;
  final ChannelDirectoryController directory;
  final VoidCallback onLoginRequested;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ChannelDirectoryStatus.signedOut:
        return Center(
          child: FilledButton.icon(
            onPressed: directory.isAuthenticated ? null : onLoginRequested,
            icon: const Icon(Icons.login_rounded),
            label: const Text('登录或注册'),
          ),
        );
      case ChannelDirectoryStatus.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading channels'),
            ],
          ),
        );
      case ChannelDirectoryStatus.failure:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_outlined, size: 30),
                const SizedBox(height: 10),
                Text(
                  directory.error?.message ?? 'Channels could not be loaded',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: directory.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case ChannelDirectoryStatus.ready:
        return const SizedBox.shrink();
    }
  }
}
