import 'package:flutter/material.dart';

/// No DM backend is deployed. The production destination contains no sample
/// contacts, messages, unread counts or controls pretending to send messages.
class DirectMessagesUnavailableScreen extends StatelessWidget {
  const DirectMessagesUnavailableScreen({super.key, required this.navigation});
  final Widget navigation;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('私信')),
    body: const Center(
      child: Padding(padding: EdgeInsets.all(24), child: Text('私信暂未开放')),
    ),
    bottomNavigationBar: navigation,
  );
}
