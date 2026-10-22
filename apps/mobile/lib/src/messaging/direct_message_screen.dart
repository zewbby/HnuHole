import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';
import 'direct_message_bubble.dart';
import 'direct_message_composer.dart';
import 'direct_message_models.dart';
import 'direct_message_chrome.dart';
import 'direct_message_timeline.dart';

/// Presentation only. The owner supplies the identity-pair projection and all
/// persistence/network operations; inbox identity changes must not retarget it.
class HhDirectMessageScreen extends StatefulWidget {
  const HhDirectMessageScreen({
    super.key,
    required this.view,
    required this.identities,
    required this.imageBuilder,
    required this.onSend,
    required this.onDraftChanged,
    required this.onIdentitySelected,
    required this.onPickImages,
    required this.onMessageAction,
    required this.onRetry,
    required this.onImage,
    required this.onSource,
    required this.onBack,
    this.onSaveRetry,
    this.onLoadOlder,
  });

  final DmConversationView view;
  final List<DmIdentity> identities;
  final DmImageBuilder imageBuilder;

  /// True only after the local durable queue accepts this exact intent. A false
  /// result or exception preserves the input. It is not a server success flag.
  final Future<bool> Function(DmSendIntent) onSend;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<DmIdentity> onIdentitySelected;
  final Future<List<DmImage>> Function() onPickImages;
  final Future<void> Function(DmMessageTarget, DmMessageAction) onMessageAction;
  final ValueChanged<DmMessageTarget> onRetry;
  final ValueChanged<DmImage> onImage;
  final VoidCallback onSource, onBack;
  final VoidCallback? onSaveRetry;
  final Future<void> Function(DmHistoryRequest)? onLoadOlder;

  @override
  State<HhDirectMessageScreen> createState() => _HhDirectMessageScreenState();
}

class _HhDirectMessageScreenState extends State<HhDirectMessageScreen> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  final List<DmImage> _images = [];
  bool _queueing = false;
  int _generation = 0;
  int _scopeEpoch = 0;
  String? _selectedMessage, _selectedImage;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.view.draftText);
  }

  @override
  void didUpdateWidget(covariant HhDirectMessageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = oldWidget.view.scopeKey != widget.view.scopeKey;
    if (!scopeChanged &&
        oldWidget.view.selfIdentity?.id != widget.view.selfIdentity?.id) {
      // An upstream first-identity change also invalidates an older enqueue.
      _scopeEpoch++;
      _generation++;
      _queueing = false;
    }
    if (scopeChanged ||
        oldWidget.view.draftRevision != widget.view.draftRevision) {
      _generation++;
      _text.value = TextEditingValue(
        text: widget.view.draftText,
        selection: TextSelection.collapsed(
          offset: widget.view.draftText.length,
        ),
      );
    }
    if (scopeChanged) {
      _scopeEpoch++;
      _images.clear();
      _queueing = false;
      _selectedMessage = _selectedImage = null;
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _identity() async {
    if (widget.view.identityLocked || _queueing) return;
    final scope = widget.view.scopeKey;
    final epoch = _scopeEpoch;
    var selected = widget.view.selfIdentity?.id;
    final result = await showModalBottomSheet<DmIdentity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final p = HhTelegramPalette.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.secondary.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择发送身份',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '首次发送后，这段对话将固定使用该身份',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: p.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final identity in widget.identities)
                          ListTile(
                            key: ValueKey('identity:${identity.id}'),
                            contentPadding: EdgeInsets.zero,
                            minVerticalPadding: 12,
                            leading: HhDmAvatar(identity: identity),
                            title: Text(identity.name),
                            trailing: Icon(
                              selected == identity.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected == identity.id
                                  ? p.accent
                                  : p.secondary,
                            ),
                            selected: selected == identity.id,
                            onTap: () => update(() => selected = identity.id),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('dm-use-identity'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 50),
                    ),
                    onPressed: selected == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            widget.identities.firstWhere(
                              (identity) => identity.id == selected,
                            ),
                          ),
                    child: const Text('使用此身份'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted &&
        epoch == _scopeEpoch &&
        widget.view.scopeKey == scope &&
        !widget.view.identityLocked &&
        result != null) {
      widget.onIdentitySelected(result);
    }
  }

  Future<void> _pickImages() async {
    final scope = widget.view.scopeKey;
    final epoch = _scopeEpoch;
    final result = await widget.onPickImages();
    if (!mounted ||
        epoch != _scopeEpoch ||
        widget.view.scopeKey != scope ||
        !widget.view.canSend) {
      return;
    }
    final unique = {for (final image in _images) image.id: image};
    for (final image in result) {
      unique[image.id] = image;
    }
    if (unique.length > 9) _notice('每次最多发送9张图片');
    setState(() {
      _generation++;
      _images
        ..clear()
        ..addAll(unique.values.take(9));
    });
  }

  Future<void> _send() async {
    final view = widget.view;
    if (_queueing || !view.canSend || view.waitingForReply) return;
    if (view.firstContact && _images.isNotEmpty) {
      _notice('对方回复前不允许发送图片');
      return;
    }
    if (_text.text.trim().isEmpty && _images.isEmpty) return;
    if (view.selfIdentity == null) {
      await _identity();
      return; // Identity selection is never an implicit send or binding.
    }
    final generation = _generation;
    final epoch = _scopeEpoch;
    final intent = DmSendIntent(
      scopeKey: view.scopeKey,
      identityId: view.selfIdentity!.id,
      text: _text.text,
      images: List.unmodifiable(_images),
    );
    setState(() => _queueing = true);
    try {
      final accepted = await widget.onSend(intent);
      if (!mounted ||
          epoch != _scopeEpoch ||
          widget.view.scopeKey != intent.scopeKey) {
        return;
      }
      if (accepted && generation == _generation) {
        _text.clear();
        _images.clear();
        widget.onDraftChanged('');
      } else if (!accepted) {
        _notice('消息尚未保存，请重试');
      }
    } catch (_) {
      if (mounted &&
          epoch == _scopeEpoch &&
          widget.view.scopeKey == intent.scopeKey) {
        _notice('消息尚未保存，请重试');
      }
    } finally {
      if (mounted &&
          epoch == _scopeEpoch &&
          widget.view.scopeKey == intent.scopeKey) {
        setState(() => _queueing = false);
      }
    }
  }

  Future<void> _retry(DmMessage message) async {
    if (message.state != DmSendState.failed || !widget.view.canSend) return;
    final epoch = _scopeEpoch;
    final target = DmMessageTarget(
      scopeKey: widget.view.scopeKey,
      messageId: message.id,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新发送这条消息？'),
        content: const Text(
          '将使用原来的身份重新发送，内容保持不变。',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新发送'),
          ),
        ],
      ),
    );
    if (mounted &&
        epoch == _scopeEpoch &&
        confirmed == true &&
        widget.view.scopeKey == target.scopeKey &&
        widget.view.canSend &&
        widget.view.messages.any(
          (m) => m.id == message.id && m.state == DmSendState.failed,
        )) {
      widget.onRetry(target);
    }
  }

  Future<void> _menu(
    DmMessage message,
    String? imageId,
    BuildContext anchor,
  ) async {
    final scope = widget.view.scopeKey;
    final epoch = _scopeEpoch;
    final target = DmMessageTarget(
      scopeKey: scope,
      messageId: message.id,
      imageId: imageId,
    );
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    setState(() {
      _selectedMessage = message.id;
      _selectedImage = imageId;
    });
    final actions = <(DmMessageAction, String, IconData)>[
      if (imageId == null && message.text.isNotEmpty)
        (DmMessageAction.copy, '复制', Icons.copy_outlined),
      (DmMessageAction.delete, '删除', Icons.delete_outline_rounded),
      if (message.outgoing &&
          message.canRecall &&
          message.state == DmSendState.sent)
        (DmMessageAction.recall, '撤回', Icons.undo_rounded),
      if (!message.outgoing)
        (DmMessageAction.report, '举报', Icons.flag_outlined),
    ];
    final action = await showMenu<DmMessageAction>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final (action, label, icon) in actions)
          PopupMenuItem(
            value: action,
            height: 48,
            child: Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 20),
                Text(label),
              ],
            ),
          ),
      ],
    );
    if (!mounted || epoch != _scopeEpoch) return;
    setState(() {
      _selectedMessage = _selectedImage = null;
    });
    final stillAvailable = widget.view.messages.where(
      (m) => m.id == message.id,
    );
    if (action != null &&
        widget.view.scopeKey == scope &&
        stillAvailable.isNotEmpty &&
        (action != DmMessageAction.recall ||
            (stillAvailable.first.canRecall &&
                stillAvailable.first.state == DmSendState.sent))) {
      await widget.onMessageAction(target, action);
    }
  }

  void _reedit(DmMessage message) {
    final text = message.reeditableText;
    if (text == null || !widget.view.canSend || widget.view.waitingForReply) {
      return;
    }
    setState(() {
      _generation++;
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
    widget.onDraftChanged(text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final p = HhTelegramPalette.of(context);
    final epoch = _scopeEpoch;
    void source() {
      if (mounted && epoch == _scopeEpoch && !widget.view.sourceDeleted) {
        widget.onSource();
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: HhDmWallpaper(
        child: SafeArea(
          child: Column(
            children: [
              HhDmHeader(
                view: view,
                onSource: source,
                onBack: () {
                  if (_focus.hasFocus) {
                    _focus.unfocus();
                  } else {
                    widget.onBack();
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Material(
                  color: p.surface.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: view.sourceDeleted ? null : source,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 18,
                            color: p.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              view.sourceDeleted
                                  ? '原帖已删除'
                                  : '来自：${view.sourceTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.secondary,
                              ),
                            ),
                          ),
                          if (!view.sourceDeleted)
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: p.secondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (view.localSaveFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '部分聊天记录未保存，请清理空间后重试',
                          style: TextStyle(fontSize: 13, color: p.error),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onSaveRetry,
                        child: const Text('重试保存'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: HhDmTimeline(
                  view: view,
                  imageBuilder: widget.imageBuilder,
                  onLoadOlder: widget.onLoadOlder,
                  selectedMessage: _selectedMessage,
                  selectedImage: _selectedImage,
                  onMenu: _menu,
                  onImage: widget.onImage,
                  onRetry: _retry,
                  onReedit: _reedit,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: HhDirectMessageComposer(
                  view: view,
                  text: _text,
                  focus: _focus,
                  images: _images,
                  imageBuilder: widget.imageBuilder,
                  queueing: _queueing,
                  onIdentity: _identity,
                  onPickImages: _pickImages,
                  onSend: _send,
                  onRemoveImage: (image) => setState(() {
                    _generation++;
                    _images.remove(image);
                  }),
                  onTextChanged: (text) {
                    setState(() => _generation++);
                    widget.onDraftChanged(text);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
