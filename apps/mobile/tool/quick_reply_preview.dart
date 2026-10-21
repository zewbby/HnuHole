// Isolated visual proposal only. No production route, session or network calls.

import 'package:flutter/material.dart';

import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';
import 'package:hnuhole_mobile/src/comments/quick_reply_dialog.dart';

const _posts = [
  FeedPostView(
    id: 'study',
    authorId: 'pine',
    authorName: '松间',
    elapsed: '8分钟前',
    title: '周末想找个安静的自习搭子',
    body: '打算周六上午去图书馆，各学各的，\n中午可以一起吃饭。有人一起吗？',
    comments: 12,
    likes: 86,
    views: 3250,
    availableActions: {
      FeedAction.comment,
      FeedAction.like,
      FeedAction.bookmark,
      FeedAction.share,
    },
  ),
  FeedPostView(
    id: 'walk',
    authorId: 'coast',
    authorName: '南岸来信',
    elapsed: '23分钟前',
    title: '傍晚的校园，随手记录',
    body: '下课以后沿着湖边走了一圈，风刚刚好。',
    comments: 31,
    likes: 238,
    views: 18600,
    availableActions: {
      FeedAction.comment,
      FeedAction.like,
      FeedAction.bookmark,
      FeedAction.share,
    },
    media: [FeedMediaView(id: 'lake', description: '合成湖边插画')],
  ),
  FeedPostView(
    id: 'meal',
    authorId: 'lime',
    authorName: '青柠汽水',
    elapsed: '42分钟前',
    title: '三食堂有什么值得试试的？',
    comments: 19,
    likes: 45,
    views: 1650,
  ),
];

TextStyle _type(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  height: 1.5,
  fontWeight: weight,
  color: color ?? HhTelegramPalette.of(context).ink,
);

class ReplyProposal extends StatefulWidget {
  const ReplyProposal({super.key, required this.target});
  final String target;
  @override
  State<ReplyProposal> createState() => _ReplyProposalState();
}

class _ReplyProposalState extends State<ReplyProposal> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => QuickReplyDialog(
    targetName: widget.target,
    controller: controller,
    onReply: () {},
    onClose: () => Navigator.pop(context),
  );
}

class Preview extends StatelessWidget {
  const Preview({super.key});
  @override
  Widget build(BuildContext context) {
    final base = HhTelegramTheme.create(Brightness.light, fontFamily: 'Roboto');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamilyFallback: ['HhNotoSansSC'],
        ),
      ),
      home: Builder(
        builder: (context) => HhXPostFeed(
          channelTitle: '推荐',
          feedTitle: '推荐',
          posts: _posts,
          avatarBuilder: (context, post) => ClipOval(
            child: ColoredBox(
              color: switch (post.authorId) {
                'pine' => const Color(0xFF7F9A8B),
                'coast' => const Color(0xFF7194AB),
                _ => const Color(0xFFA0A57A),
              },
              child: Center(
                child: Text(
                  post.authorName.characters.first,
                  style: _type(
                    context,
                    22,
                    color: Colors.white,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          mediaBuilder: (_, _) => const CustomPaint(painter: _Lake()),
          onPost: (_) =>
              throw StateError('The quick reply must keep the feed open'),
          onAction: (post, action) {
            if (action == FeedAction.comment) {
              showDialog<void>(
                context: context,
                barrierColor: Colors.black.withValues(alpha: .30),
                builder: (_) => ReplyProposal(target: post.authorName),
              );
            }
          },
          onAuthor: (_) {},
          onMedia: (_, _) {},
          onMenu: (_) {},
          onBack: () {},
          onSearch: () {},
          onFilter: () {},
          onCompose: () {},
          onDestination: (_) {},
        ),
      ),
    );
  }
}

class _Lake extends CustomPainter {
  const _Lake();
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE0EAE6));
    c.drawRect(
      Rect.fromLTWH(0, s.height * .48, s.width, s.height),
      Paint()..color = const Color(0xFFB5CED1),
    );
    c.drawCircle(
      Offset(s.width * .76, s.height * .27),
      s.width * .08,
      Paint()..color = const Color(0xFFFFF1C9),
    );
    final land = Path()
      ..moveTo(0, s.height * .42)
      ..quadraticBezierTo(
        s.width * .42,
        s.height * .30,
        s.width,
        s.height * .54,
      )
      ..lineTo(s.width, s.height * .63)
      ..quadraticBezierTo(s.width * .35, s.height * .46, 0, s.height * .59)
      ..close();
    c.drawPath(land, Paint()..color = const Color(0xFF739584));
    for (var i = 0; i < 5; i++) {
      c.drawLine(
        Offset(s.width * .12, s.height * (.7 + i * .045)),
        Offset(s.width * (.4 + i * .08), s.height * (.7 + i * .045)),
        Paint()
          ..color = const Color(0xFFDDE8E6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Lake old) => false;
}

void main() => runApp(const Preview());
