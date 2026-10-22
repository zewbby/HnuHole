import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_inbox.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';

import 'src/dm_preview_fixtures.dart';

/// Explicit development target. No accounts, network, disk queue or receipts.
void main() {
  HhTelegramTheme.registerFontLicenses();
  runApp(const DmPreviewApp());
}

class DmPreviewApp extends StatefulWidget {
  const DmPreviewApp({super.key});
  @override
  State<DmPreviewApp> createState() => _DmPreviewAppState();
}

class _DmPreviewAppState extends State<DmPreviewApp> {
  bool dark = false;
  AppDestination destination = AppDestination.directMessages;
  DmIdentity identity = dmPreviewIdentities.first;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: HhTelegramTheme.create(Brightness.light),
    darkTheme: HhTelegramTheme.create(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => Column(
      children: [
        Material(
          color: HhTelegramPalette.of(context).surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Center(
                child: Text(
                  '开发预览 · 不连接私信服务',
                  style: TextStyle(
                    fontSize: 11,
                    color: HhTelegramPalette.of(context).secondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child!,
          ),
        ),
      ],
    ),
    home: Builder(
      builder: (context) => destination != AppDestination.directMessages
          ? _otherDestination(context)
          : HhDmInboxScreen(
              scopeKey: 'preview/${identity.id}',
              identity: identity,
              identities: [
                for (final i in dmPreviewIdentities)
                  DmInboxIdentity(i, unread: i.id == identity.id ? 0 : 2),
              ],
              onIdentitySelected: (value) => setState(() => identity = value),
              entries: [
                for (final (index, scene) in [
                  'normal',
                  'first-contact',
                  'failed',
                  'unknown',
                  'waiting',
                  'history',
                  'identity-lost',
                  'save-failed',
                ].indexed)
                  DmInboxEntry(
                    id: scene,
                    selfIdentityId: identity.id,
                    recipient: DmIdentity(
                      id: 'preview-$scene',
                      name: [
                        '海边的树',
                        '科科',
                        '图书馆同学',
                        '晚潮',
                        '风里的信',
                        '云朵收集者',
                        '旧相识',
                        '山海',
                      ][index],
                    ),
                    preview: [
                      '[图片] 从这边走，树荫多一点。',
                      '还没有消息',
                      '发送失败，点击进入确认重试',
                      '消息结果待核对',
                      '等待对方回复',
                      '向上查看本地历史样例',
                      '对方身份已失效',
                      '部分记录未保存',
                    ][index],
                    time: index == 0 ? '21:56' : '昨天',
                    unread: index == 0 ? 3 : 0,
                    pinned: index == 0,
                    outgoingState: scene == 'failed'
                        ? DmSendState.failed
                        : scene == 'unknown'
                        ? DmSendState.unknown
                        : null,
                  ),
              ],
              onOpen: (target) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _ConversationDemo(scene: target.conversationId),
                ),
              ),
              navigation: _navigation(),
            ),
    ),
  );

  Widget _navigation() => HhAppNavigation(
    selected: destination,
    onSelected: (value) => setState(() => destination = value),
  );

  Widget _otherDestination(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (destination) {
        AppDestination.home => '首页',
        AppDestination.messages => '消息',
        AppDestination.personal => '我的',
        AppDestination.directMessages => '私信',
      }),
      actions: [
        IconButton(
          tooltip: '切换预览外观',
          onPressed: () => setState(() => dark = !dark),
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
      ],
    ),
    body: Center(
      child: Text(
        destination == AppDestination.messages ? '预览未连接通知服务' : '请在日常 App 查看此页面',
      ),
    ),
    bottomNavigationBar: _navigation(),
  );
}

class _ConversationDemo extends StatefulWidget {
  const _ConversationDemo({required this.scene});
  final String scene;
  @override
  State<_ConversationDemo> createState() => _ConversationDemoState();
}

class _ConversationDemoState extends State<_ConversationDemo> {
  late final controller = DmPreviewController(widget.scene);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => HhDirectMessageScreen(
      view: controller.view,
      identities: dmPreviewIdentities,
      imageBuilder: (_, image) => DmPreviewImage(image: image),
      onSend: controller.acceptLocally,
      onDraftChanged: (text) => controller.draft = text,
      onIdentitySelected: controller.selectIdentity,
      onPickImages: () async => dmPreviewImages,
      onRetry: controller.retry,
      onLoadOlder: controller.loadOlder,
      onMessageAction: (target, action) async {
        if (action == DmMessageAction.copy) {
          await Clipboard.setData(
            ClipboardData(
              text: controller.messages
                  .firstWhere((m) => m.id == target.messageId)
                  .text,
            ),
          );
        } else if (action == DmMessageAction.delete) {
          controller.act(target, action);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('此预览不执行服务端撤回或举报')));
        }
      },
      onImage: (image) => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: AspectRatio(
            aspectRatio: 1,
            child: DmPreviewImage(image: image),
          ),
        ),
      ),
      onSource: () =>
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('预览：最初来源帖入口'))),
      onSaveRetry: () =>
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('预览未接入本地消息仓库'))),
      onBack: () => Navigator.maybePop(context),
    ),
  );
}
