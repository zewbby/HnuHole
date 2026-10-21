// Isolated layout proposal. Synthetic content, no production route or API.

import 'package:flutter/material.dart';
import 'package:hnuhole_mobile/src/design_system/detail_components.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';

class XDetailLayoutPreview extends StatelessWidget {
  const XDetailLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: HhTelegramTheme.create(Brightness.light),
    home: const _DetailPage(),
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();
  static const ink = HhTelegramPalette.lightInk;
  static const muted = HhTelegramPalette.lightSecondary;
  static const blue = HhTelegramPalette.lightAccent;
  static const line = HhTelegramPalette.lightLine;
  static const iconInk = Color(0xFF59666D);

  TextStyle type(
    BuildContext context,
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = ink,
    double height = 1.45,
  }) => Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: 0,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );

  Widget avatar(
    BuildContext context,
    String name,
    Color color,
    double radius,
  ) => Container(
    width: radius * 2,
    height: radius * 2,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, .13)!,
          Color.lerp(color, Colors.black, .07)!,
        ],
      ),
    ),
    child: Text(
      name,
      style: type(
        context,
        radius * .85,
        color: Colors.white,
        weight: FontWeight.w500,
      ),
    ),
  );

  Widget glyph(FeedAction action, {double size = 24, Color color = iconInk}) =>
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: DetailGlyph(action, color, false)),
      );

  Widget action(BuildContext context, FeedAction action, String? count) =>
      SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph(action),
            if (count != null) ...[
              const SizedBox(width: 7),
              Text(count, style: type(context, 14, color: iconInk)),
            ],
          ],
        ),
      );

  Widget comment(
    BuildContext context, {
    required String name,
    required String letter,
    required Color color,
    required String time,
    required String body,
    required String likes,
    String replies = '',
    bool author = false,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar(context, letter, color, 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type(context, 16, weight: FontWeight.w500),
                          ),
                        ),
                        if (author) ...[
                          const SizedBox(width: 5),
                          Text(
                            '楼主',
                            style: type(
                              context,
                              11.5,
                              color: blue,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          '· $time',
                          style: type(context, 12.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const DetailChromeIcon(
                    DetailChrome.more,
                    color: iconInk,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(body, style: type(context, 16, height: 1.45)),
              const SizedBox(height: 12),
              Row(
                children: [
                  glyph(FeedAction.comment, size: 18),
                  if (replies.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(replies, style: type(context, 12, color: muted)),
                  ],
                  const SizedBox(width: 49),
                  glyph(FeedAction.like, size: 18),
                  const SizedBox(width: 5),
                  Text(likes, style: type(context, 12, color: muted)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 12, 19, 6),
          child: Row(
            children: [
              Text('13:08', style: type(context, 13, weight: FontWeight.w500)),
              const Spacer(),
              const Icon(Icons.signal_cellular_alt, size: 15, color: ink),
              const SizedBox(width: 5),
              const Icon(Icons.wifi, size: 15, color: ink),
              const SizedBox(width: 5),
              const Icon(Icons.battery_6_bar, size: 17, color: ink),
            ],
          ),
        ),
        SizedBox(
          height: 57,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const SizedBox(
                width: 40,
                child: Center(
                  child: DetailChromeIcon(
                    DetailChrome.back,
                    size: 25,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text('帖子', style: type(context, 20, weight: FontWeight.w500)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 17, 0, 0),
                  child: Row(
                    children: [
                      avatar(context, '松', const Color(0xFF18ADBA), 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '松间',
                              style: type(context, 17, weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 3),
                            Text('搭子', style: type(context, 14, color: muted)),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: DetailChromeIcon(
                            DetailChrome.more,
                            size: 22,
                            color: iconInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 0),
                  child: Text(
                    '周末想找个安静的自习搭子',
                    style: type(context, 18, weight: FontWeight.w500),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 9, 8, 0),
                  child: Text(
                    '打算周六上午去图书馆，各学各的，\n中午可以一起吃饭。\n\n有人一起吗？学累了就去校园里走走。',
                    style: type(context, 16, height: 1.5),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '10月21日 13:08 · ',
                          style: type(context, 13.5, color: muted),
                        ),
                        TextSpan(
                          text: '3,286',
                          style: type(context, 13.5, weight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: ' 次浏览',
                          style: type(context, 13.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      action(context, FeedAction.comment, '3'),
                      action(context, FeedAction.like, '86'),
                      action(context, FeedAction.bookmark, '12'),
                      action(context, FeedAction.share, null),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: .6, color: line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 3),
                  child: Text(
                    '评论',
                    style: type(context, 17, weight: FontWeight.w500),
                  ),
                ),
                Stack(
                  children: [
                    const Positioned(
                      left: 31.5,
                      top: 53,
                      bottom: 65,
                      child: ColoredBox(
                        color: Color(0xFFDADFE1),
                        child: SizedBox(width: 1),
                      ),
                    ),
                    Column(
                      children: [
                        comment(
                          context,
                          name: '青柠汽水',
                          letter: '柠',
                          color: const Color(0xFF83A95B),
                          time: '12分钟',
                          body: '我也在准备期末！周六上午可以一起，坐靠窗那边。',
                          likes: '5',
                          replies: '1',
                        ),
                        comment(
                          context,
                          name: '松间',
                          letter: '松',
                          color: const Color(0xFF18ADBA),
                          time: '8分钟',
                          body: '好呀，九点图书馆门口见～',
                          likes: '3',
                          author: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 1, thickness: .6, color: line),
                comment(
                  context,
                  name: '南岸来信',
                  letter: '南',
                  color: const Color(0xFF639CC2),
                  time: '5分钟',
                  body: '下午也想去，学累了一起去食堂。',
                  likes: '2',
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: line, width: .6)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Container(
            height: 55,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F5),
              borderRadius: BorderRadius.circular(29),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                avatar(context, '海', blue, 18),
                const SizedBox(width: 11),
                Expanded(
                  child: Text('发布你的回复', style: type(context, 16, color: muted)),
                ),
                const DetailChromeIcon(
                  DetailChrome.image,
                  color: iconInk,
                  size: 26,
                ),
                const SizedBox(width: 17),
                const DetailChromeIcon(
                  DetailChrome.expand,
                  color: iconInk,
                  size: 23,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 23,
          child: Center(
            child: Container(
              width: 118,
              height: 4,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
