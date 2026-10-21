import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design_system/telegram_theme.dart';
import 'direct_message_models.dart';

typedef DmImageBuilder = Widget Function(BuildContext context, DmImage image);

class HhDirectMessageBubble extends StatelessWidget {
  const HhDirectMessageBubble({
    super.key,
    required this.message,
    required this.imageBuilder,
    required this.onMenu,
    required this.onImage,
    required this.onRetry,
    required this.onReedit,
    this.joinsPrevious = false,
    this.joinsNext = false,
    this.selectedImageId,
    this.selected = false,
  });
  final DmMessage message;
  final DmImageBuilder imageBuilder;
  final void Function(String? imageId, BuildContext anchor) onMenu;
  final ValueChanged<DmImage> onImage;
  final VoidCallback onRetry, onReedit;
  final bool joinsPrevious, joinsNext, selected;
  final String? selectedImageId;

  @override
  Widget build(BuildContext context) {
    final palette = HhTelegramPalette.of(context);
    if (message.recalled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              message.outgoing ? '你撤回了一条消息' : '对方撤回了一条消息',
              style: TextStyle(fontSize: 12, color: palette.secondary),
            ),
            if (message.outgoing && message.reeditableText != null)
              TextButton(onPressed: onReedit, child: const Text('重新编辑')),
          ],
        ),
      );
    }
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth * (large ? .91 : .83),
          constraints.maxWidth - 48,
        );
        final color = selected
            ? palette.selection
            : message.outgoing
            ? palette.outgoing
            : palette.incoming;
        final radius = BorderRadius.only(
          topLeft: Radius.circular(!message.outgoing && joinsPrevious ? 5 : 17),
          topRight: Radius.circular(message.outgoing && joinsPrevious ? 5 : 17),
          bottomLeft: Radius.circular(!message.outgoing && joinsNext ? 5 : 17),
          bottomRight: Radius.circular(message.outgoing && joinsNext ? 5 : 17),
        );
        final bubble = Stack(
          clipBehavior: Clip.none,
          children: [
            if (!joinsNext)
              Positioned(
                bottom: 0,
                left: message.outgoing ? null : -5,
                right: message.outgoing ? -5 : null,
                child: CustomPaint(
                  size: const Size(9, 12),
                  painter: _BubbleTail(color, message.outgoing),
                ),
              ),
            Material(
              color: color,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: message.images.isEmpty
                    ? _text(context, width)
                    : _media(context, width),
              ),
            ),
          ],
        );
        final children = <Widget>[
          if (message.outgoing && message.state != DmSendState.sent)
            SizedBox(
              width: 48,
              height: 48,
              child: message.state == DmSendState.failed
                  ? IconButton(
                      key: ValueKey('retry:${message.id}'),
                      tooltip: '发送失败，选择是否重发',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: onRetry,
                      icon: Icon(
                        Icons.error_outline_rounded,
                        color: palette.error,
                        size: 21,
                      ),
                    )
                  : Semantics(
                      label: '正在发送，结果尚未确认',
                      child: Center(
                        child: MediaQuery.disableAnimationsOf(context)
                            ? Icon(
                                Icons.timelapse_rounded,
                                size: 19,
                                color: palette.secondary,
                              )
                            : SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: palette.secondary,
                                ),
                              ),
                      ),
                    ),
            ),
          bubble,
        ];
        return Padding(
          padding: EdgeInsets.only(top: joinsPrevious ? 3 : 9),
          child: Row(
            mainAxisAlignment: message.outgoing
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: children,
          ),
        );
      },
    );
  }

  Widget _text(BuildContext context, double width) {
    final palette = HhTelegramPalette.of(context);
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 16,
      height: 1.4,
      color: palette.ink,
      fontWeight: FontWeight.w400,
    );
    final timeStyle = style.copyWith(
      fontSize: 12,
      height: 1.25,
      color: message.outgoing ? palette.outgoingTime : palette.secondary,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final available = math.max(32.0, width - 24);
    final painter = TextPainter(
      text: TextSpan(text: message.text, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: available);
    final time = TextPainter(
      text: TextSpan(text: message.time, style: timeStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final lines = painter.computeLineMetrics();
    final lastWidth = lines.isEmpty ? 0.0 : lines.last.width;
    final inline = lastWidth + time.width + 12 <= available;
    final desired = math.min(
      available,
      math.max(
        48.0,
        inline
            ? math.max(painter.width, lastWidth + time.width + 12)
            : painter.width,
      ),
    );
    painter.dispose();
    time.dispose();
    return Builder(
      builder: (anchor) => Semantics(
        excludeSemantics: true,
        label:
            '${message.outgoing ? '本人' : '对方'}：${message.text}，${message.time}',
        customSemanticsActions: {
          const CustomSemanticsAction(label: '消息操作'): () =>
              onMenu(null, anchor),
        },
        child: InkWell(
          onLongPress: () => onMenu(null, anchor),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
            child: SizedBox(
              width: desired,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: inline ? 1 : scaler.scale(17),
                    ),
                    child: Text(message.text, style: style),
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: Text(message.time, style: timeStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _media(BuildContext context, double width) {
    final palette = HhTelegramPalette.of(context);
    final count = message.images.length;
    final columns = count == 1
        ? 1
        : count <= 4
        ? 2
        : 3;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(3),
            itemCount: count,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: count == 1 ? 1.65 : 1.12,
            ),
            itemBuilder: (context, index) {
              final image = message.images[index];
              return Builder(
                builder: (anchor) => Semantics(
                  label: image.description,
                  button: true,
                  customSemanticsActions: {
                    const CustomSemanticsAction(label: '图片操作'): () =>
                        onMenu(image.id, anchor),
                  },
                  child: Material(
                    color: palette.background,
                    child: InkWell(
                      onTap: () => onImage(image),
                      onLongPress: () => onMenu(image.id, anchor),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          imageBuilder(context, image),
                          if (selectedImageId == image.id)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: palette.accent,
                                  width: 3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 6, 11, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.text.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Builder(
                      builder: (anchor) => InkWell(
                        onLongPress: () => onMenu(null, anchor),
                        child: Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  message.time,
                  style: TextStyle(
                    fontSize: 12,
                    color: message.outgoing
                        ? palette.outgoingTime
                        : palette.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail(this.color, this.outgoing);
  final Color color;
  final bool outgoing;
  @override
  void paint(Canvas canvas, Size size) {
    if (!outgoing) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(2, 8, 9, 12)
      ..quadraticBezierTo(2, 12, 0, 10)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubbleTail oldDelegate) =>
      color != oldDelegate.color || outgoing != oldDelegate.outgoing;
}
