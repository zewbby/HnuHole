import 'package:flutter/material.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';

const dmPreviewIdentities = [
  DmIdentity(id: 'fixture-lime', name: '青柠汽水'),
  DmIdentity(id: 'fixture-tide', name: '晚潮'),
  DmIdentity(id: 'fixture-cloud', name: '云朵收集者'),
];
const dmPreviewImages = [
  DmImage(id: 'fixture-east-gate', description: '东门入口示意图'),
  DmImage(id: 'fixture-library', description: '图书馆步行路线示意图'),
];

/// Memory-only fixtures. They deliberately implement no durable queue, receipt,
/// account access, backend acceptance, recall deadline, or persistent draft.
class DmPreviewController extends ChangeNotifier {
  DmPreviewController(this.scene) {
    if (scene == 'first-contact') self = null;
    if (scene == 'first-contact' || scene == 'waiting') {
      messages = scene == 'waiting'
          ? [
              const DmMessage(
                id: 'first',
                outgoing: true,
                time: '09:41',
                text: '你好，想问一下自习室怎么预约？',
              ),
            ]
          : [];
    } else {
      messages = [
        const DmMessage(
          id: 'hello',
          outgoing: false,
          time: '09:32',
          text: '看到你问图书馆的帖子了。',
        ),
        const DmMessage(
          id: 'answer',
          outgoing: false,
          time: '09:32',
          text: '东门现在可以进，二楼有一片安静的自习区。',
        ),
        const DmMessage(
          id: 'question',
          outgoing: true,
          time: '09:34',
          text: '太好了！从宿舍过去走哪条路比较近？',
        ),
        const DmMessage(
          id: 'photos',
          outgoing: false,
          time: '09:35',
          text: '从这边走，树荫多一点。',
          images: dmPreviewImages,
        ),
        DmMessage(
          id: 'thanks',
          outgoing: true,
          time: '09:36',
          text: '收到，谢谢你！我下午去看看。',
          canRecall: true,
          state: scene == 'failed'
              ? DmSendState.failed
              : scene == 'unknown'
              ? DmSendState.unknown
              : DmSendState.sent,
        ),
        if (scene == 'recall')
          const DmMessage(
            id: 'recall',
            outgoing: true,
            time: '09:37',
            recalled: true,
            reeditableText: '我下午三点到。',
          ),
      ];
    }
    if (scene == 'history') {
      messages = [
        for (var i = 0; i < 35; i++)
          DmMessage(
            id: 'history-$i',
            outgoing: i.isOdd,
            time: '12:${i.toString().padLeft(2, '0')}',
            text: '第${i + 1}条本地历史样例。向上浏览时保持当前位置。',
            dayLabel: '10月21日',
          ),
      ];
    }
  }

  final String scene;
  DmIdentity? self = dmPreviewIdentities.first;
  late List<DmMessage> messages;
  String draft = '';
  bool accepted = false;
  bool olderLoaded = false;

  DmConversationView get view => DmConversationView(
    scopeKey: 'fixture-pair',
    recipient: const DmIdentity(id: 'fixture-woods', name: '海边的树'),
    privateNote: scene == 'note' ? '图书馆同学' : null,
    sourceTitle: '图书馆东门现在开放吗？',
    selfIdentity: self,
    identityLocked: scene != 'first-contact' || accepted,
    firstContact: scene == 'first-contact' || scene == 'waiting',
    firstTextAccepted: accepted || scene == 'waiting',
    sourceDeleted: scene == 'source-deleted',
    canSend: scene != 'identity-lost',
    localSaveFailed: scene == 'save-failed',
    messages: List.unmodifiable(messages),
    draftText: draft,
    dayLabel: '10月21日',
    firstUnreadMessageId: scene == 'normal' ? 'answer' : null,
    historyState: scene == 'history' && !olderLoaded
        ? DmHistoryState.available
        : DmHistoryState.complete,
    historyCursor: scene == 'history' && !olderLoaded ? 'history-0' : null,
  );

  Future<void> loadOlder(DmHistoryRequest request) async {
    if (scene != 'history' || olderLoaded) return;
    messages = [
      for (var i = 0; i < 20; i++)
        DmMessage(
          id: 'older-$i',
          outgoing: i.isOdd,
          time: '18:${i.toString().padLeft(2, '0')}',
          text: '更早的第${i + 1}条本地样例。',
          dayLabel: '10月20日',
        ),
      ...messages,
    ];
    olderLoaded = true;
    notifyListeners();
  }

  void selectIdentity(DmIdentity identity) {
    self = identity;
    notifyListeners();
  }

  Future<bool> acceptLocally(DmSendIntent intent) async {
    // An immediate memory acceptance exercises the presentation callback only.
    // Production must replace this with the local durable queue adapter.
    messages = [
      ...messages,
      DmMessage(
        id: 'preview-${messages.length}',
        outgoing: true,
        time: '09:41',
        text: intent.text,
        images: intent.images,
        state: DmSendState.unknown,
      ),
    ];
    accepted = true;
    notifyListeners();
    return true;
  }

  void retry(DmMessageTarget target) {
    messages = [
      for (final m in messages)
        m.id == target.messageId ? m.copyWith(state: DmSendState.unknown) : m,
    ];
    notifyListeners();
  }

  void act(DmMessageTarget target, DmMessageAction action) {
    if (action == DmMessageAction.delete) {
      messages = [
        for (final m in messages)
          if (m.id != target.messageId)
            m
          else if (target.imageId != null)
            DmMessage(
              id: m.id,
              outgoing: m.outgoing,
              time: m.time,
              text: m.text,
              images: m.images.where((i) => i.id != target.imageId).toList(),
              state: m.state,
              canRecall: m.canRecall,
            ),
      ];
    }
    // Recall/report need authoritative adapters; no pretend success in this demo.
    notifyListeners();
  }
}

/// Code-drawn fixture images, not real user photos or downloaded media.
class DmPreviewImage extends StatelessWidget {
  const DmPreviewImage({super.key, required this.image});
  final DmImage image;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CampusMap(
      image.id.endsWith('library'),
      Theme.of(context).textTheme.bodyMedium?.fontFamily,
    ),
  );
}

class _CampusMap extends CustomPainter {
  const _CampusMap(this.library, this.fontFamily);
  final bool library;
  final String? fontFamily;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFD8E4D1),
    );
    canvas.save();
    canvas.scale(size.width / 160, size.height / 145);
    final road = Path()
      ..moveTo(-10, 118)
      ..cubicTo(40, 87, 88, 132, 170, 14);
    canvas.drawPath(
      road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 23
        ..color = const Color(0xFFF1ECDA),
    );
    canvas.drawPath(
      road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFCFC6AF),
    );
    final building = library
        ? const Rect.fromLTWH(23, 15, 73, 45)
        : const Rect.fromLTWH(20, 20, 89, 38);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        building.shift(const Offset(2, 3)),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF9EAF9A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(building, const Radius.circular(3)),
      Paint()..color = const Color(0xFFFBFAF2),
    );
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawRect(
          Rect.fromLTWH(
            building.left + 8 + i * 16,
            building.top + 8 + j * 14,
            8,
            6,
          ),
          Paint()..color = const Color(0xFF8EA3A4),
        );
      }
    }
    for (final point in [
      const Offset(18, 78),
      const Offset(135, 41),
      const Offset(138, 119),
      const Offset(65, 135),
    ]) {
      canvas.drawCircle(
        point + const Offset(1, 2),
        13,
        Paint()..color = const Color(0xFFADC3A0),
      );
      canvas.drawCircle(point, 11, Paint()..color = const Color(0xFF87A77D));
    }
    final route = Path()
      ..moveTo(14, 119)
      ..quadraticBezierTo(89, 95, 125, 53);
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3E7F9E),
    );
    canvas.drawCircle(
      const Offset(125, 53),
      5,
      Paint()..color = const Color(0xFF3E7F9E),
    );
    final text = TextPainter(
      text: TextSpan(
        text: library ? '图书馆' : '东门',
        style: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: const ['HhNotoSansSC'],
          color: const Color(0xFF334838),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(25, 66));
    text.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampusMap oldDelegate) =>
      library != oldDelegate.library || fontFamily != oldDelegate.fontFamily;
}
