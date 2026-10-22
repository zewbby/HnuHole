import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;

import 'package:flutter/foundation.dart';

import '../posts/post_api.dart';
import 'dm_protocol.dart';
import 'dm_store.dart';

part 'dm_chat_controller.dart';

typedef DmStoreFactory = Future<DmStore> Function(String account);

/// A controller owns one authorized session window. Its store is permanently
/// bound to the account; async replies never consult a newly selected account.
class DmController extends ChangeNotifier {
  DmController({
    required this.api,
    required this.openStore,
    this.onUnauthorized,
    this.onUnavailable,
    this.onMetadata,
    this.chatEnabled = false,
  });
  final DmApi api;
  final bool chatEnabled;
  final DmStoreFactory openStore;
  final void Function(String, String?)? onUnauthorized;
  final void Function(String)? onUnavailable;
  final Future<void> Function(String, DateTime, bool Function())? onMetadata;
  DmStore? _store;
  String? _account, _token;
  int _epoch = 0;
  int _bindingGeneration = 0;
  bool _disposed = false;
  bool Function()? _authorized;
  List<String> _identities = [];
  Future<void>? _syncing;
  Timer? _timer;
  List<Map<String, dynamic>> conversations = [];
  String? error;
  String? _operationError;
  bool get available =>
      _store != null && _authorized?.call() == true && !_disposed;
  String get scope => '${_account ?? ''}:$_epoch';

  Future<void> bind({
    required String account,
    required String token,
    required List<String> identities,
    required bool Function() isCurrent,
  }) async {
    final binding = ++_bindingGeneration;
    await _disconnect();
    if (_disposed || binding != _bindingGeneration || !isCurrent()) return;
    final epoch = ++_epoch;
    _account = account;
    _token = token;
    _identities = List.of(identities);
    _authorized = isCurrent;
    try {
      final store = await openStore(account);
      if (!_current(epoch)) {
        await store.close();
        return;
      }
      _store = store;
      await _refreshDirectory(epoch, store);
      if (!_current(epoch)) return;
      _notify();
      _timer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(sync()),
      );
      await sync();
    } catch (_) {
      if (_current(epoch)) {
        error = '私信本地保存不可用，输入不会被清除';
        _notify();
      }
    }
  }

  bool _current(int epoch) =>
      !_disposed && _epoch == epoch && _authorized?.call() == true;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> detach() async {
    _bindingGeneration++;
    await _disconnect();
  }

  Future<void> _disconnect() async {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _authorized = null;
    final store = _store;
    _store = null;
    _account = null;
    _token = null;
    conversations = [];
    error = null;
    _operationError = null;
    _notify();
    // Drain the old window before opening a new store and starting another loop.
    await _syncing;
    await store?.close();
  }

  Future<void> sync() {
    if (_syncing != null) return _syncing!;
    if (!available) return Future.value();
    final task = _synchronize(_epoch, _store!, _token!);
    _syncing = task;
    return task.whenComplete(() => _syncing = null);
  }

  Future<Map<String, dynamic>> _request(
    int epoch,
    String token,
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (!_current(epoch)) throw StateError('DM window expired');
    final response = await api.dmRequest(
      token,
      method,
      path,
      body: body,
      query: query,
    );
    if (!_current(epoch)) throw StateError('DM window expired');
    await onMetadata?.call(
      token,
      response.sessionExpiresAt,
      () => _current(epoch),
    );
    if (!_current(epoch)) throw StateError('DM window expired');
    return response.value;
  }

  Future<void> _synchronize(int epoch, DmStore store, String token) async {
    try {
      if (chatEnabled) await _chatBeforeSync(epoch, store, token);
      for (final row in await store.work()) {
        if (!_current(epoch)) return;
        final id = row['_id'] as String;
        final state = row['_state'] as String;
        if (state == 'queued' || state == 'unknown') {
          final intent = Map<String, Object>.from(row['intent'] as Map);
          if (state == 'queued') {
            await store.transition(id, 'queued', 'unknown');
          }
          if (!_current(epoch)) return;
          var receipt = await _request(epoch, token, 'GET', 'commands/$id');
          if (row['_kind'] == 'hidden_message' && receipt['state'] != 'SENT') {
            await store.transition(id, 'unknown', 'deleted');
            continue;
          }
          if (receipt['state'] == 'ABSENT' ||
              receipt['state'] == 'FAILED' &&
                  (receipt['attempt'] as int) < (intent['attempt'] as int)) {
            final image = row['messageType'] == 'IMAGE';
            if (image) {
              intent['data'] = base64Encode(
                await store.photo(intent['mediaId'] as String),
              );
            }
            receipt = await _request(
              epoch,
              token,
              'PUT',
              image ? 'chat/images/$id' : 'commands/$id',
              body: intent,
            );
          }
          if (!_current(epoch)) return;
          if (receipt['attempt'] != intent['attempt'] ||
              !{'SENT', 'FAILED'}.contains(receipt['state'])) {
            throw const FormatException('DM attempt mismatch');
          }
          await store.transition(
            id,
            'unknown',
            receipt['state'] == 'SENT' ? 'sent' : 'failed',
            receipt: receipt,
          );
          if (chatEnabled && receipt['state'] == 'SENT') {
            await store.enforceDeleteFor(id);
            final control = await store.get(
              'retracted:${receipt['messageId']}',
            );
            if (control != null) {
              await store.applyControls([control], await store.controlCursor());
            }
          }
          if (chatEnabled) await store.eraseHiddenResolved(id);
        } else {
          final read = state == 'read_pending';
          await _request(
            epoch,
            token,
            'POST',
            read ? 'read' : 'ack',
            body: {
              'messageIds': [id],
            },
          );
          if (!_current(epoch)) return;
          await store.transition(id, state, read ? 'read' : 'inbox');
          if (chatEnabled) await store.eraseHiddenResolved(id);
        }
      }
      final pending = await _request(
        epoch,
        token,
        'GET',
        chatEnabled ? 'chat/pending' : 'pending',
      );
      final items = (pending['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (items.isNotEmpty) {
        if (!_current(epoch)) return;
        final durableIds = <String>[];
        if (chatEnabled) {
          for (final item in items) {
            try {
              if (await store.deliverySuppressed(item)) {
                durableIds.add(item['messageId']);
                continue;
              }
              final previous = await store.get(item['messageId']);
              if (previous != null) {
                durableIds.add(item['messageId']);
                continue;
              }
              if (item['kind'] == 'IMAGE') {
                final media = await _request(
                  epoch,
                  token,
                  'GET',
                  'chat/media/${item['messageId']}',
                );
                if (media['messageId'] != item['messageId'] ||
                    media['mediaId'] != (item['media'] as Map)['mediaId'] ||
                    media['sha256'] != (item['media'] as Map)['sha256']) {
                  throw const FormatException('Mismatched private image');
                }
                final bytes = base64Decode(media['data'] as String);
                if (bytes.length != media['byteLength'] ||
                    hashes.sha256.convert(bytes).toString() !=
                        media['sha256']) {
                  throw const FormatException('Damaged private image');
                }
                if (!_current(epoch)) return;
                await store.receivePhoto(item, bytes);
              } else {
                await store.receive([item]);
              }
              durableIds.add(item['messageId']);
            } on PostFailure catch (e) {
              if (e.kind == PostFailureKind.unauthorized ||
                  e.kind == PostFailureKind.unavailable) {
                rethrow;
              }
              _operationError = '部分聊天记录未保存，请清理空间或恢复连接后重试';
            } catch (_) {
              _operationError = '部分聊天记录未保存，请清理空间或恢复连接后重试';
            }
          }
        } else {
          await store.receive(items);
          durableIds.addAll(items.map((e) => e['messageId'] as String));
        }
        if (!_current(epoch)) return;
        if (durableIds.isNotEmpty) {
          await _request(
            epoch,
            token,
            'POST',
            'ack',
            body: {'messageIds': durableIds},
          );
          if (!_current(epoch)) return;
          for (final item in items) {
            if (!durableIds.contains(item['messageId'])) continue;
            final row = await store.get(item['messageId']);
            if (!_current(epoch)) return;
            if (row?['_state'] == 'received') {
              await store.transition(item['messageId'], 'received', 'inbox');
            }
          }
        }
      }
      for (final identity in _identities) {
        var after = '';
        do {
          final page = await _request(
            epoch,
            token,
            'GET',
            chatEnabled ? 'chat/conversations' : 'conversations',
            query: {
              'identityId': identity,
              if (after.isNotEmpty) 'after': after,
            },
          );
          final rows = (page['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (rows.any((e) => e['identityId'] != identity)) {
            throw const FormatException('DM identity mismatch');
          }
          if (!_current(epoch)) return;
          if (chatEnabled) {
            await store.saveChatConversations(rows);
          } else {
            await store.saveConversations(rows);
          }
          if (rows.length < 100) break;
          final next = rows.last['id'] as String;
          if (next.compareTo(after) <= 0) {
            throw const FormatException('DM pagination stalled');
          }
          after = next;
        } while (_current(epoch));
      }
      if (chatEnabled) await _chatControls(epoch, store, token);
      if (!_current(epoch)) return;
      error = _operationError;
      _operationError = null;
    } on PostFailure catch (e) {
      if (!_current(epoch)) return;
      if (e.kind == PostFailureKind.unauthorized) {
        onUnauthorized?.call(token, e.code);
      } else if (e.kind == PostFailureKind.unavailable) {
        onUnavailable?.call(token);
      }
      if (!_current(epoch)) return;
      error = '连接暂不可用，已保存内容将在恢复后继续核对';
    } catch (_) {
      if (_current(epoch)) {
        error = '同步暂未完成，已保存内容保留，稍后自动核对';
      }
    } finally {
      if (_current(epoch)) {
        try {
          await _refreshDirectory(epoch, store);
        } catch (_) {}
        if (_current(epoch)) _notify();
      }
    }
  }

  Future<void> _refreshDirectory(int epoch, DmStore store) async {
    final directory = (await store.conversations())
        .where((v) => _identities.contains(v['identityId']))
        .toList();
    for (final v in directory) {
      final local = await store.history(v['identityId'], v['peerId'], limit: 1);
      if (!_current(epoch)) return;
      if (local.isNotEmpty) {
        final last = local.single;
        v['localPreview'] = last['recalled'] == true
            ? '消息已撤回'
            : last['messageType'] == 'IMAGE'
            ? '[图片]'
            : last['outgoing'] == true
            ? (last['intent'] as Map)['text']
            : last['text'];
        v['localOrdinal'] = last['_ordinal'];
        v['localState'] = last['outgoing'] == true ? last['_state'] : null;
      }
      if (chatEnabled) {
        v['localSearchText'] = await store.searchText(
          v['identityId'],
          v['peerId'],
        );
      }
    }
    directory.sort(
      (a, b) =>
          (b['pinned'] == true ? 1 : 0).compareTo(
                a['pinned'] == true ? 1 : 0,
              ) !=
              0
          ? (b['pinned'] == true ? 1 : 0).compareTo(a['pinned'] == true ? 1 : 0)
          : ((b['localOrdinal'] as int?) ?? 0).compareTo(
              (a['localOrdinal'] as int?) ?? 0,
            ),
    );
    if (!_current(epoch)) return;
    conversations = directory;
  }

  Future<bool> send(Map<String, Object> intent, {String peerName = ''}) async {
    if (!available || !_identities.contains(intent['identityId'])) return false;
    final epoch = _epoch;
    final store = _store!;
    try {
      await store.enqueue(intent, peerName: peerName);
      if (!_current(epoch)) return false;
      // The enqueue commit is authoritative. A later projection/read failure
      // must not report enqueue failure and invite a duplicate user send.
      try {
        await _refreshDirectory(epoch, store);
      } catch (_) {}
      if (!_current(epoch)) return false;
      _notify();
      unawaited(sync());
      return true;
    } catch (_) {
      if (_current(epoch)) {
        error = '保存失败，请保留输入并重试';
        _notify();
      }
      return false;
    }
  }

  Future<void> retry(String id) async {
    if (!available) return;
    final epoch = _epoch;
    final store = _store!;
    try {
      await store.retry(id);
      if (_current(epoch)) {
        _notify();
        await sync();
      }
    } catch (_) {
      if (_current(epoch)) {
        error = '原消息暂时无法重试';
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> contact(String post, String comment) async {
    if (!available) throw StateError('DM unavailable');
    return _request(
      _epoch,
      _token!,
      'GET',
      'contact',
      query: {'postId': post, if (comment.isNotEmpty) 'commentId': comment},
    );
  }

  Future<void> saveDraft(String own, String peer, String text) async {
    if (!available || !_identities.contains(own)) return;
    final epoch = _epoch;
    try {
      await _store!.saveDraft(own, peer, text);
    } catch (_) {
      if (_current(epoch)) {
        error = '草稿保存失败，请保留当前页面';
        _notify();
      }
    }
  }

  Future<String> draft(String own, String peer) async =>
      available ? _store!.draft(own, peer) : '';
  Future<Map<String, dynamic>?> message(String id) async {
    if (!available) return null;
    final epoch = _epoch;
    final row = await _store!.get(id);
    return _current(epoch) ? row : null;
  }

  Future<List<Map<String, dynamic>>> history(
    String own,
    String peer, {
    int? before,
  }) async {
    if (!available || !_identities.contains(own)) return [];
    final epoch = _epoch;
    final rows = await _store!.history(own, peer, before: before);
    return _current(epoch) ? rows : [];
  }

  Future<void> visible(List<String> ids) async {
    if (!available || ids.isEmpty) return;
    final epoch = _epoch;
    try {
      final changed = await _store!.markVisible(ids);
      if (changed && _current(epoch)) unawaited(sync());
    } catch (_) {
      if (_current(epoch)) {
        error = '阅读状态尚未保存';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detach());
    super.dispose();
  }
}
