import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'feed_chrome.dart';

/// Owns the four peer destinations. Detail routes remain on the outer Navigator.
/// A changed authority window discards every visited tab, including empty data.
class PrimaryTabs extends StatefulWidget {
  const PrimaryTabs({
    super.key,
    required this.window,
    required this.builders,
    required this.onSelected,
  });
  final (String?, int) window;
  final Map<AppDestination, WidgetBuilder> builders;
  final ValueChanged<AppDestination> onSelected;

  @override
  State<PrimaryTabs> createState() => PrimaryTabsState();
}

class PrimaryTabsState extends State<PrimaryTabs> {
  AppDestination _selected = AppDestination.home;
  final _visited = {AppDestination.home};
  FeedChromeController _chrome = FeedChromeController();

  void select(AppDestination destination) {
    if (!mounted || _selected == destination) return;
    _chrome.show();
    setState(() {
      _selected = destination;
      _visited.add(destination);
    });
  }

  @override
  void didUpdateWidget(PrimaryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      final previous = _chrome;
      _chrome = FeedChromeController();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      _selected = AppDestination.home;
      _visited
        ..clear()
        ..add(AppDestination.home);
    }
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CoveredRouteInsets(child: Builder(builder: _buildTabs));

  Widget _buildTabs(BuildContext context) => PopScope(
    canPop: _selected == AppDestination.home,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) select(AppDestination.home);
    },
    child: Scaffold(
      extendBody: _selected == AppDestination.home,
      body: Builder(
        builder: (bodyContext) => MediaQuery(
          // extendBody adds the navigation's height to body padding. Home draws
          // under the sliding bar and needs only the real system safe inset.
          // Other tabs already have a shortened Scaffold body, just as before.
          data: MediaQuery.of(bodyContext).copyWith(
            padding: MediaQuery.paddingOf(context).copyWith(
              bottom: _selected == AppDestination.home
                  ? MediaQuery.paddingOf(context).bottom
                  : 0,
            ),
          ),
          child: FeedChromeScope(
            controller: _chrome,
            child: IndexedStack(
              index: _selected.index,
              children: [
                for (final destination in AppDestination.values)
                  TickerMode(
                    key: ValueKey((widget.window, destination)),
                    enabled: destination == _selected,
                    child: _visited.contains(destination)
                        ? Builder(builder: widget.builders[destination]!)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FeedNavigation(
        controller: _chrome,
        selected: _selected,
        onSelected: widget.onSelected,
        collapseSpace: true,
      ),
    ),
  );
}

/// A detail/editor route owns its keyboard. Keep the covered tab tree at its
/// normal viewport instead of rebuilding and laying it out behind that route
/// for every IME inset change. Rotation and authority changes still propagate.
class _CoveredRouteInsets extends StatelessWidget {
  const _CoveredRouteInsets({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: ModalRoute.isCurrentOf(context) == false
          ? media.copyWith(
              viewInsets: EdgeInsets.zero,
              padding: media.viewPadding,
            )
          : media,
      child: child,
    );
  }
}
