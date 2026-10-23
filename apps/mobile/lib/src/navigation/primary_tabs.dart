import 'package:flutter/material.dart';

import 'app_navigation.dart';

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

  void select(AppDestination destination) {
    if (!mounted || _selected == destination) return;
    setState(() {
      _selected = destination;
      _visited.add(destination);
    });
  }

  @override
  void didUpdateWidget(PrimaryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      _selected = AppDestination.home;
      _visited
        ..clear()
        ..add(AppDestination.home);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected == AppDestination.home,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) select(AppDestination.home);
    },
    child: Scaffold(
      body: IndexedStack(
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
      bottomNavigationBar: HhAppNavigation(
        selected: _selected,
        onSelected: widget.onSelected,
      ),
    ),
  );
}
