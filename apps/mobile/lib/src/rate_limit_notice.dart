import 'dart:async';

import 'package:flutter/material.dart';

import 'rate_limit.dart';

/// Local presentation timer only. Expiry never submits or polls the network.
class RateLimitDraftNotice extends StatefulWidget {
  const RateLimitDraftNotice({
    super.key,
    required this.remaining,
    required this.onRetry,
  });
  final int Function() remaining;
  final VoidCallback? onRetry;
  @override
  State<RateLimitDraftNotice> createState() => _RateLimitDraftNoticeState();
}

class _RateLimitDraftNoticeState extends State<RateLimitDraftNotice> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.remaining();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seconds > 0 ? rateLimitDraftMessage(seconds) : '等待结束，内容已保存为草稿，请手动重试。',
        ),
        TextButton(
          onPressed: seconds > 0 ? null : widget.onRetry,
          child: const Text('重试原草稿'),
        ),
      ],
    );
  }
}
